use std::{cell::RefCell, collections::HashMap, panic::catch_unwind};

use anyhow::{anyhow, Context, Result};
use chrono::{Duration, NaiveDate};
use kline_dsl::{
    mod_def::registry::ModuleRegistry,
    pipeline::{IndicatorCall, Mark, Pipeline, PrepareStage, Stage, StageResult, WindowMatch},
    ScreenResult, Timeframe, WindowSize,
};
use polars::prelude::*;
use rayon::prelude::*;

use crate::{
    cache::IntradayCache,
    compiler::indicator::compile_mod,
    evaluator::{
        ctx::EvalCtx,
        expr::{eval_bool, eval_num, resolve_path_row},
        point::resolve_points,
    },
    matcher::match_pattern,
    planner::{plan_stage, StagePlan},
    provider::DataProvider,
    DateIndex, MatchedWindow,
};

/// 运行 Pipeline，返回 Polars DataFrame（group_by 结果 + passed/eliminated_reason 列）。
pub type IntradayLoader<'a> = &'a (dyn Fn(&str, NaiveDate) -> Option<DataFrame> + Sync);

pub fn run_pipeline_df(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    from: NaiveDate,
    to: NaiveDate,
    load_intraday: Option<IntradayLoader<'_>>,
) -> DataFrame {
    let plans: Vec<StagePlan> = pipeline
        .stages
        .iter()
        .map(|stage| plan_stage(stage, registry))
        .collect::<Result<Vec<_>>>()
        .unwrap_or_else(|e| { eprintln!("[run_pipeline_df] plan_stage failed: {e}"); vec![] });
    if plans.is_empty() {
        eprintln!("[run_pipeline_df] all stages failed planning, returning empty");
        return DataFrame::empty();
    }
    let tf = pipeline.stages.first().map(|s| s.timeframe).unwrap_or(Timeframe::Daily);
    if let Some(df) = try_run_batch_df(pipeline, registry, provider, symbols, tf, from, to, &plans) {
        return df;
    }
    let results = run_pipeline_with_intraday(pipeline, registry, provider, symbols, from, to, load_intraday);
    screen_results_to_df(&results, to)
}

fn screen_results_to_df(results: &[ScreenResult], target_date: NaiveDate) -> DataFrame {
    let n = results.len();
    let mut markets: Vec<i32> = Vec::with_capacity(n);
    let mut codes: Vec<i32> = Vec::with_capacity(n);
    let mut passed: Vec<bool> = Vec::with_capacity(n);
    let mut reasons: Vec<String> = Vec::with_capacity(n);
    let mut elim_stage: Vec<String> = Vec::with_capacity(n);
    let mut stage_trace: Vec<String> = Vec::with_capacity(n);
    let mut dates: Vec<Option<String>> = Vec::with_capacity(n);

    for r in results {
        let (mkt, code) = parse_symbol_for_run(&r.symbol).unwrap_or((-1, -1));
        markets.push(mkt);
        codes.push(code);
        let ok = r.eliminated_at.is_none();
        passed.push(ok);
        reasons.push(r.eliminated_reason.clone().unwrap_or_default());
        elim_stage.push(r.eliminated_at.clone().unwrap_or_default());
        // Compact trace: "stage1✓(cond1,cond2) → stage2✗(cond3=failed_reason)"
        let trace_parts: Vec<String> = r.stage_results.iter().map(|sr| {
            let status = if sr.passed { "✓" } else { "✗" };
            let conds: Vec<&str> = sr.passed_conditions.iter().map(|s| s.as_str()).collect();
            let detail = if sr.passed {
                conds.join(",")
            } else {
                format!("{}={}", sr.failed_condition.as_deref().unwrap_or("?"), conds.join(","))
            };
            format!("{}{}({})", sr.stage_name, status, detail)
        }).collect();
        stage_trace.push(trace_parts.join(" → "));
        dates.push(Some(target_date.format("%Y-%m-%d").to_string()));
    }

    let mut df = DataFrame::new(n, vec![
        Column::new("market".into(), Series::new("market".into(), markets)),
        Column::new("code".into(), Series::new("code".into(), codes)),
        Column::new("passed".into(), Series::new("passed".into(), passed)),
        Column::new("eliminated_reason".into(), Series::new("eliminated_reason".into(), reasons)),
        Column::new("eliminated_stage".into(), Series::new("eliminated_stage".into(), elim_stage)),
        Column::new("stage_trace".into(), Series::new("stage_trace".into(), stage_trace)),
        Column::new("date".into(), Series::new("date".into(), dates)),
    ]).unwrap_or_default();

    let sys_names: &[(&str, &str)] = &[
        ("market", "市场"), ("code", "代码"), ("date", "日期"),
        ("passed", "通过"), ("eliminated_reason", "淘汰原因"),
        ("eliminated_stage", "淘汰阶段"), ("stage_trace", "阶段痕迹"),
    ];
    for (en, cn) in sys_names {
        let _ = df.rename(*en, PlSmallStr::from_str(cn));
    }
    df
}

/// Batch 路径返回 DataFrame 版本。
fn try_run_batch_df(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    tf: Timeframe,
    from: NaiveDate,
    to: NaiveDate,
    plans: &[StagePlan],
) -> Option<DataFrame> {
    if pipeline.stages.len() != 1 || !pipeline.stages[0].extra_stocks.is_empty() { return None; }
    let stage = &pipeline.stages[0];
    let plan = &plans[0];

    let (expanded_from, expanded_to) = expand_date_range(from, to, tf, plan);

    // 1. Load
    let mut lf = provider.load_batch_joined_lf(symbols, tf, expanded_from, expanded_to)?;

    // 2. Pattern
    let mut patt_col: Option<String> = None;
    if let Some(ref pat) = stage.kline_pattern {
        let ws = stage.windowsize.unwrap_or(WindowSize::Range { min: None, max: None });
        if let Ok(partitions) = crate::matcher::polars_pattern::compile_partitions(&pat.pattern, ws) {
            if !partitions.is_empty() {
                let mut combined: Option<Expr> = None;
                for p in &partitions { combined = match combined { None => Some(p.expr.clone()), Some(e) => Some(e.or(p.expr.clone())) }; }
                if let Some(expr) = combined { let cn = "_patt".to_string(); lf = lf.with_column(expr.alias(cn.clone())); patt_col = Some(cn); }
            }
        }
    }

    // 3. Indicators
    for exprs in &plan.compiled_indicators { lf = lf.with_columns(exprs.clone()); }

    // 4. Conditions (market conditions skipped, handled in Rust)
    let compiled_all = crate::compiler::expr_compiler::compile_conditions(&stage.conditions);
    let has_market = stage.conditions.iter().any(|(_,e)| expr_has_market_ref(e));
    let mut col_aliases: Vec<String> = Vec::new();
    let mut col_reasons: Vec<String> = Vec::new();
    let mut market_cond_names: Vec<String> = Vec::new();
    let mut comp_idx = 0;
    for (name, expr) in &stage.conditions {
        if has_market && expr_has_market_ref(expr) { market_cond_names.push(name.clone()); }
        else if comp_idx < compiled_all.len()
            && crate::compiler::expr_compiler::try_compile_condition(name, expr).is_some()
        { let c = &compiled_all[comp_idx]; comp_idx += 1; lf = lf.with_column(c.expr.clone().alias(c.column_name.clone())); col_aliases.push(c.column_name.clone()); col_reasons.push(c.condition_name.clone()); }
        else { return None; }
    }

    // 5. Market data lookup table
    let market_table: HashMap<(NaiveDate, i32), (f64, f64)> = if has_market {
        let mut tbl = HashMap::new();
        for (mkt, code) in [(0,399001),(1,1),(2,899050)] {
            let sym = format!("{}.{code:06}", match mkt { 0=>"SZ", 1=>"SH", _=>"BJ" });
            if let Ok(df) = provider.kline(&sym, tf, expanded_from, expanded_to).collect() {
                let dates = crate::extract_dates(&df);
                let close = crate::extract_f64_col(&df, "close");
                let open = crate::extract_f64_col(&df, "open");
                for i in 0..df.height().min(dates.len()).min(close.len()).min(open.len()) {
                    tbl.insert((dates[i], mkt), (close[i], open[i]));
                }
            }
        }
        tbl
    } else { HashMap::new() };

    // 6. Symbol filter join
    let sym_markets: Vec<i32> = symbols.iter().filter_map(|s| parse_symbol_for_run(s)).map(|(m,_)| m).collect();
    let sym_codes: Vec<i32> = symbols.iter().filter_map(|s| parse_symbol_for_run(s)).map(|(_,c)| c).collect();
    if sym_markets.is_empty() { return None; }
    let sym_tbl = DataFrame::new(sym_markets.len(), vec![
        Column::new("_m".into(), Series::new("_m".into(), sym_markets)),
        Column::new("_c".into(), Series::new("_c".into(), sym_codes)),
    ]).ok()?;
    lf = lf.join(sym_tbl.lazy(), [col("market"), col("code")], [col("_m"), col("_c")], JoinArgs::new(JoinType::Inner));

    // 7. Group_by
    let mut agg_exprs: Vec<Expr> = col_aliases.iter().map(|c| col(c.as_str()).last())
        .chain([col("date").last(), col("close").last(), col("open").last()].into_iter()).collect();
    if let Some(ref pc) = patt_col { agg_exprs.push(col(pc.as_str()).last()); }
    agg_exprs.extend(plan.indicator_columns.iter().map(|c| col(c.as_str()).last()));
    let mut grouped = match catch_unwind(std::panic::AssertUnwindSafe(|| {
        lf.group_by([col("market"), col("code")]).agg(&agg_exprs).collect()
    })) {
        Ok(Ok(g)) => g,
        _ => return None,
    };

    // 8. Add passed + eliminated_reason columns
    let n = grouped.height();
    let market_s = grouped.column("market").ok()?.i32().ok()?;
    let code_s = grouped.column("code").ok()?.i32().ok()?;
    let mut passed_vec: Vec<bool> = Vec::with_capacity(n);
    let mut reason_vec: Vec<String> = Vec::with_capacity(n);
    for i in 0..n {
        let m = market_s.get(i).unwrap_or(-1);
        let (mut ok, mut reason) = (true, String::new());
        if let Some(ref pc) = patt_col {
            if let Some(false) = grouped.column(pc.as_str()).ok().and_then(|s| s.bool().ok()).and_then(|c| c.get(i)) {
                ok = false; reason = "形态不匹配".into();
            }
        }
        if ok {
            for (j, alias) in col_aliases.iter().enumerate() {
                if let Some(false) = grouped.column(alias.as_str()).ok().and_then(|s| s.bool().ok()).and_then(|c| c.get(i)) {
                    ok = false; reason = col_reasons[j].clone(); break;
                }
            }
        }
        if ok && has_market {
            let close = grouped.column("close").ok().and_then(|s| s.f64().ok()).and_then(|c| c.get(i));
            let open = grouped.column("open").ok().and_then(|s| s.f64().ok()).and_then(|c| c.get(i));
            let date_str = grouped.column("date").ok().and_then(|s| s.str().ok()).and_then(|c| c.get(i));
            let date = date_str.and_then(|ds| NaiveDate::parse_from_str(ds, "%Y-%m-%d").ok());
            let stock_up = match (close, open) { (Some(c), Some(o)) => c > o, _ => false };
            let mkt_up = date.and_then(|d| market_table.get(&(d, m))).map(|&(c,o)| c > o).unwrap_or(false);
            if stock_up == mkt_up { ok = false; reason = "counter_market".into(); }
        }
        if !ok && reason.is_empty() { reason = "unknown".into(); }
        passed_vec.push(ok);
        reason_vec.push(if ok { String::new() } else { reason });
    }
    let _ = grouped.with_column(Column::new("passed".into(), Series::new("passed".into(), passed_vec)));
    let _ = grouped.with_column(Column::new("eliminated_reason".into(), Series::new("eliminated_reason".into(), reason_vec)));

    // 系统列中文化
    let sys_names: &[(&str, &str)] = &[
        ("market", "市场"), ("code", "代码"), ("symbol", "代码"),
        ("date", "日期"), ("open", "开盘"), ("high", "最高"),
        ("low", "最低"), ("close", "收盘"), ("volume", "成交量"),
        ("amount", "成交额"), ("_patt", "形态匹配"),
        ("passed", "通过"), ("eliminated_reason", "淘汰原因"),
    ];
    for (en, cn) in sys_names {
        let _ = grouped.rename(*en, PlSmallStr::from_str(cn));
    }
    Some(grouped)
}

pub fn run_pipeline(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    from: NaiveDate,
    to: NaiveDate,
) -> Vec<ScreenResult> {
    run_pipeline_with_intraday(pipeline, registry, provider, symbols, from, to, None)
}

pub fn run_pipeline_with_intraday(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    from: NaiveDate,
    to: NaiveDate,
    load_intraday: Option<IntradayLoader<'_>>,
) -> Vec<ScreenResult> {
    let plans: Vec<StagePlan> = pipeline
        .stages
        .iter()
        .map(|stage| plan_stage(stage, registry))
        .collect::<Result<Vec<_>>>()
        .unwrap_or_else(|e| {
            eprintln!("[run_pipeline] plan_stage failed: {e}");
            vec![]
        });
    if plans.is_empty() {
        eprintln!("[run_pipeline] all stages failed planning, returning no results");
        return vec![];
    }

    let tf = pipeline.stages.first().map(|s| s.timeframe).unwrap_or(Timeframe::Daily);
    let mut all_symbols: Vec<String> = symbols.to_vec();
    all_symbols.extend(["SH.000001", "SZ.399001", "BJ.899050"].iter().map(|s| s.to_string()));

    if pipeline.stages.len() == 1
        && pipeline.stages[0].extra_stocks.is_empty()
    {
        if let Some((batch_results, deferred)) = try_run_batch_grouped(pipeline, registry, provider, symbols, &all_symbols, tf, from, to, &plans) {
            if deferred.is_empty() {
                return batch_results; // All conditions compiled; results are final
            }
            // Two-phase: batch kline done, now per-symbol intraday for survivors
            let survivors: Vec<String> = batch_results.iter()
                .filter(|r| r.eliminated_at.is_none())
                .map(|r| r.symbol.clone())
                .collect();
            if survivors.is_empty() {
                return batch_results; // No symbol passed kline phase
            }

            // Build Phase 2 pipeline: pattern + points kept (cheap on cached data), only deferred conditions
            let mut p2_stage = pipeline.stages[0].clone();
            p2_stage.conditions = deferred.clone();
            // Keep kline_pattern, points, vars — needed for intraday anchor resolution
            // Keep prepare/indicators — needed for computed columns
            let p2 = Pipeline { stages: vec![p2_stage] };
            let p2_plans: Vec<StagePlan> = p2.stages.iter()
                .map(|s| plan_stage(s, registry))
                .collect::<Result<Vec<_>>>()
                .unwrap_or_default();
            if p2_plans.is_empty() { return batch_results; }

            // Only load survivors + market indexes for Phase 2 (not all 5000+ symbols)
            let mut p2_load_symbols: Vec<String> = survivors.clone();
            p2_load_symbols.extend(["SH.000001", "SZ.399001", "BJ.899050"].iter().map(|s| s.to_string()));
            let cache = provider.load_batch(&p2_load_symbols, tf, from, to);
            let mut bp = HashMapProvider::new(cache, Some(provider));
            bp.load_intraday = load_intraday;
            let ip: HashMapProvider;
            let intraday_ref2: &dyn DataProvider;
            if load_intraday.is_some() {
                ip = HashMapProvider { data: HashMap::new(), fallback: None, load_intraday };
                intraday_ref2 = &ip;
            } else {
                intraday_ref2 = provider;
            }

            // Evaluate deferred conditions on survivors in parallel (std::thread::scope)
            let num_threads = 6usize;
            let chunk_size = (survivors.len() / num_threads).max(1);
            let p2_total = survivors.len();
            let p2_done = std::sync::atomic::AtomicUsize::new(0);
            let p2_start = std::time::Instant::now();
            let p2_results: Vec<ScreenResult> = std::thread::scope(|s| {
                let mut handles = Vec::new();
                for chunk in survivors.chunks(chunk_size) {
                    handles.push(s.spawn(|| {
                        chunk.iter().map(|sym| {
                            let r = match run_pipeline_for_symbol(&p2, registry, &bp, intraday_ref2, sym, from, to, &p2_plans) {
                                Ok(r) => r,
                                Err(e) => ScreenResult {
                                    symbol: sym.clone(), passed_stages: vec![],
                                    eliminated_at: Some("error".into()), eliminated_reason: Some(format!("{e}")),
                                    stage_results: vec![],
                                },
                            };
                            let done = p2_done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
                            if done % 50 == 0 || done == p2_total {
                                let elapsed = p2_start.elapsed().as_secs_f64();
                                eprintln!("[SCREENER_PROGRESS] phase=2 processed={done} total={p2_total} elapsed={elapsed:.1}s");
                            }
                            r
                        }).collect::<Vec<_>>()
                    }));
                }
                handles.into_iter().flat_map(|h| h.join().unwrap()).collect()
            });

            // Merge Phase 1 + Phase 2 results
            let mut final_results = Vec::new();
            for mut r in batch_results {
                if r.eliminated_at.is_none() {
                    // This symbol passed Phase 1 — check Phase 2
                    if let Some(p2r) = p2_results.iter().find(|p| p.symbol == r.symbol) {
                        if let Some(ref reason) = p2r.eliminated_reason {
                            r.eliminated_at = p2r.eliminated_at.clone();
                            r.eliminated_reason = Some(reason.clone());
                            r.passed_stages = vec![];
                        }
                        // Merge stage results
                        if !r.stage_results.is_empty() && !p2r.stage_results.is_empty() {
                            let mut sr = r.stage_results[0].clone();
                            sr.passed_conditions.extend(p2r.stage_results[0].passed_conditions.clone());
                            if p2r.stage_results[0].failed_condition.is_some() {
                                sr.passed = false;
                                sr.failed_condition = p2r.stage_results[0].failed_condition.clone();
                            }
                            r.stage_results = vec![sr];
                        }
                    }
                }
                final_results.push(r);
            }
            return final_results;
        }
    }

    let cache = provider.load_batch(&all_symbols, tf, from, to);
    let mut batch_provider = HashMapProvider::new(cache, Some(provider));
    batch_provider.load_intraday = load_intraday;
    // Also need to inject intraday loader into the intraday_provider
    // Create a lightweight provider just for intraday
    let intraday_provider: HashMapProvider;
    let intraday_ref: &dyn DataProvider;
    if load_intraday.is_some() {
        intraday_provider = HashMapProvider {
            data: HashMap::new(),
            fallback: None,
            load_intraday,
        };
        intraday_ref = &intraday_provider;
    } else {
        intraday_ref = provider;
    }

    let per_stock_total = symbols.len();
    let per_stock_done = std::sync::atomic::AtomicUsize::new(0);
    let per_stock_start = std::time::Instant::now();
    symbols.par_iter().map(|symbol| {
        let r = match run_pipeline_for_symbol(pipeline, registry, &batch_provider, intraday_ref, symbol, from, to, &plans) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("[run_pipeline] error for {symbol}: {e}");
                ScreenResult {
                    symbol: symbol.clone(), passed_stages: vec![],
                    eliminated_at: Some("error".into()), eliminated_reason: Some(format!("{e}")),
                    stage_results: vec![],
                }
            }
        };
        let done = per_stock_done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        if done % 100 == 0 || done == per_stock_total {
            let elapsed = per_stock_start.elapsed().as_secs_f64();
            eprintln!("[SCREENER_PROGRESS] phase=per_stock processed={done} total={per_stock_total} elapsed={elapsed:.1}s");
        }
        r
    }).collect()
}

/// 尝试在大 DataFrame 上用 group_by 批量求值（全程 lazy 链）。
fn try_run_batch_grouped(
    pipeline: &Pipeline,
    _registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    _all_symbols: &[String],
    tf: Timeframe,
    from: NaiveDate,
    to: NaiveDate,
    plans: &[StagePlan],
) -> Option<(Vec<ScreenResult>, Vec<(String, kline_dsl::Expr)>)> {
    let stage = &pipeline.stages[0];
    let plan = &plans[0];

    let (expanded_from, expanded_to) = expand_date_range(from, to, tf, plan);

    // 1. 加载 LazyFrame（不 collect！）
    let mut lf = provider.load_batch_joined_lf(symbols, tf, expanded_from, expanded_to)?;

    // 2. 编译形态 → _patt 列
    let mut patt_col: Option<String> = None;
    if let Some(ref pat) = stage.kline_pattern {
        let ws = stage.windowsize.unwrap_or(kline_dsl::WindowSize::Range { min: None, max: None });
        match crate::matcher::polars_pattern::compile_partitions(&pat.pattern, ws) {
            Ok(partitions) if !partitions.is_empty() => {
                let mut combined: Option<Expr> = None;
                for p in &partitions {
                    combined = match combined {
                        None => Some(p.expr.clone()),
                        Some(e) => Some(e.or(p.expr.clone())),
                    };
                }
                if let Some(expr) = combined {
                    let col_name = "_patt".to_string();
                    lf = lf.with_column(expr.alias(col_name.clone()));
                    patt_col = Some(col_name);
                }
            }
            Ok(_) => {} // empty partitions
            Err(e) => eprintln!("[batch] compile_partitions error: {e}"),
        }
    }


    // 4. 加指标
    for exprs in &plan.compiled_indicators {
        lf = lf.with_columns(exprs.clone());
    }

    // 5. 编译条件 → 布尔列（market/intraday 条件跳过，分别后处理）
    let compiled_all = crate::compiler::expr_compiler::compile_conditions(&stage.conditions);
    let has_market = stage.conditions.iter().any(|(_,e)| expr_has_market_ref(e));
    let mut col_aliases: Vec<String> = Vec::new();
    let mut col_reasons: Vec<String> = Vec::new();
    let mut market_cond_names: Vec<String> = Vec::new();
    let mut need_per_symbol: Vec<(String, kline_dsl::Expr)> = Vec::new();
    let mut comp_idx = 0;
    for (name, expr) in &stage.conditions {
        if expr_has_market_ref(expr) {
            market_cond_names.push(name.clone());
        } else if comp_idx < compiled_all.len() && crate::compiler::expr_compiler::try_compile_condition(name, expr).is_some() {
            let c = &compiled_all[comp_idx];
            comp_idx += 1;
            lf = lf.with_column(c.expr.clone().alias(c.column_name.clone()));
            col_aliases.push(c.column_name.clone());
            col_reasons.push(c.condition_name.clone());
        } else {
            need_per_symbol.push((name.clone(), expr.clone()));
        }
    }
    let deferred_names: std::collections::HashSet<&str> = need_per_symbol.iter().map(|(n, _)| n.as_str()).collect();
    // 预加载大盘数据（精确按 date+market 查找，避免逐标路径的 row index 偏移 bug）
    let market_table: HashMap<(NaiveDate, i32), (f64, f64)> = if has_market {
        let mut tbl = HashMap::new();
        for (mkt, code) in [(0,399001),(1,1),(2,899050)] {
            let sym = format!("{}.{code:06}", match mkt { 0=>"SZ", 1=>"SH", _=>"BJ" });
            if let Ok(df) = provider.kline(&sym, tf, expanded_from, expanded_to).collect() {
                let dates = crate::extract_dates(&df);
                let close = crate::extract_f64_col(&df, "close");
                let open = crate::extract_f64_col(&df, "open");
                for i in 0..df.height().min(dates.len()) {
                    tbl.insert((dates[i], mkt), (close[i], open[i]));
                }
            }
        }
        tbl
    } else { HashMap::new() };

    // 6. 用 Inner Join 过滤：只保留请求的标的
    let sym_markets: Vec<i32> = symbols.iter().filter_map(|s| parse_symbol_for_run(s)).map(|(m,_)| m).collect();
    let sym_codes: Vec<i32> = symbols.iter().filter_map(|s| parse_symbol_for_run(s)).map(|(_,c)| c).collect();
    if sym_markets.is_empty() { return None; }
    let height = sym_markets.len();
    let sym_tbl = DataFrame::new(height, vec![
        Column::new("_m".into(), Series::new("_m".into(), sym_markets)),
        Column::new("_c".into(), Series::new("_c".into(), sym_codes)),
    ]).ok()?;
    let sym_lf = sym_tbl.lazy();
    lf = lf.join(sym_lf, [col("market"), col("code")], [col("_m"), col("_c")], JoinArgs::new(JoinType::Inner));

    // 7. group_by + 取每个标的末行（只 collect N 行！）
    let mut agg_exprs: Vec<Expr> = col_aliases.iter()
        .map(|c| col(c.as_str()).last())
        .chain([col("date").last(), col("close").last(), col("open").last()].into_iter())
        .collect();
    if let Some(ref pc) = patt_col {
        agg_exprs.push(col(pc.as_str()).last());
    }
    agg_exprs.extend(plan.indicator_columns.iter().map(|c| col(c.as_str()).last()));
    let grouped = match catch_unwind(std::panic::AssertUnwindSafe(|| {
        lf.group_by([col("market"), col("code")]).agg(&agg_exprs).collect()
    })) {
        Ok(Ok(g)) => g,
        Ok(Err(e)) => { eprintln!("[batch] group_by failed: {e}"); return None; }
        Err(_) => { eprintln!("[batch] group_by panicked"); return None; }
    };

    // 8. 构建结果
    let market_s = grouped.column("market").ok()?.i32().ok()?;
    let code_s = grouped.column("code").ok()?.i32().ok()?;
    let mut results = Vec::with_capacity(symbols.len());
    let mut seen: HashMap<String, bool> = HashMap::new();

    for i in 0..grouped.height() {
        let m = market_s.get(i).unwrap_or(-1);
        let c = code_s.get(i).unwrap_or(-1);
        let prefix = match m { 0 => "SZ", 1 => "SH", 2 => "BJ", _ => continue };
        let sym = format!("{prefix}.{c:06}");

        // 检查形态（如果存在）
        if let Some(ref pc) = patt_col {
            if let Ok(col) = grouped.column(pc.as_str()) {
                if let Ok(mask) = col.bool() {
                    if !mask.get(i).unwrap_or(false) {
                        seen.insert(sym.clone(), true);
                        results.push(ScreenResult {
                            symbol: sym.clone(), passed_stages: vec![],
                            eliminated_at: Some(stage.name.clone()),
                            eliminated_reason: Some("kline_pattern".into()),
                            stage_results: vec![kline_dsl::pipeline::StageResult {
                                stage_name: stage.name.clone(),
                                symbol: sym.clone(), passed: false,
                                passed_conditions: vec![],
                                failed_condition: Some("kline_pattern".into()),
                                resolved_points: HashMap::new(), marks: HashMap::new(),
                                matches: vec![],
                            }],
                        });
                        continue;
                    }
                }
            }
        }

        let mut all_pass = true;
        let mut fail_reason: Option<String> = None;
        for (j, alias) in col_aliases.iter().enumerate() {
            if let Ok(col) = grouped.column(alias.as_str()) {
                if let Ok(mask) = col.bool() {
                    if !mask.get(i).unwrap_or(false) {
                        all_pass = false;
                        fail_reason = Some(col_reasons[j].clone());
                        break;
                    }
                }
            }
        }
        // market 条件：精确按 date 查找（避免逐标路径 row index 偏移 bug）
        if has_market {
            let stock_close = grouped.column("close").ok().and_then(|s| s.f64().ok()).and_then(|c| c.get(i));
            let stock_open = grouped.column("open").ok().and_then(|s| s.f64().ok()).and_then(|c| c.get(i));
            let date_str = grouped.column("date").ok().and_then(|s| s.str().ok()).and_then(|c| c.get(i));
            let date = date_str.and_then(|ds| chrono::NaiveDate::parse_from_str(ds, "%Y-%m-%d").ok());
            let stock_up = match (stock_close, stock_open) { (Some(c), Some(o)) => c > o, _ => false };
            let mkt_data = date.and_then(|d| market_table.get(&(d, m)).copied());
            let mkt_up = mkt_data.map(|(close, open)| close > open).unwrap_or(false);
            if all_pass {
                for cond_name in &market_cond_names {
                    let passes = stock_up != mkt_up;
                    if !passes {
                        all_pass = false;
                        fail_reason = Some(cond_name.clone());
                        break;
                    }
                }
            }
        }
        seen.insert(sym.clone(), true);
        results.push(ScreenResult {
            symbol: sym.clone(),
            passed_stages: if all_pass { vec![stage.name.clone()] } else { vec![] },
            eliminated_at: if all_pass { None } else { Some(stage.name.clone()) },
            eliminated_reason: fail_reason.clone(),
            stage_results: vec![kline_dsl::pipeline::StageResult {
                stage_name: stage.name.clone(),
                symbol: sym.clone(), passed: all_pass,
                passed_conditions: if all_pass {
                    stage.conditions.iter()
                        .filter(|(n,_)| !deferred_names.contains(n.as_str()))
                        .map(|(n,_)| n.clone()).collect()
                } else { vec![] },
                failed_condition: fail_reason,
                resolved_points: HashMap::new(), marks: HashMap::new(),
                matches: vec![kline_dsl::pipeline::WindowMatch { window_start: 0, window_end: 1, resolved_points: HashMap::new(), marks: HashMap::new() }],
            }],
        });
    }
    for sym in symbols {
        if !seen.contains_key(sym) {
            results.push(ScreenResult {
                symbol: sym.clone(), passed_stages: vec![],
                eliminated_at: Some("no_data".into()), eliminated_reason: Some("no_data".into()),
                stage_results: vec![],
            });
        }
    }
    Some((results, need_per_symbol))
}

/// Run Phase 1 (kline batch) only, return (passing_symbols, has_deferred_intraday_conditions).
/// Caller should pre-fetch intraday data only when deferred is true and survivors > 0.
pub fn get_kline_survivors(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbols: &[String],
    from: NaiveDate,
    to: NaiveDate,
) -> (Vec<String>, bool) {
    if pipeline.stages.len() != 1 || !pipeline.stages[0].extra_stocks.is_empty() {
        return (symbols.to_vec(), false);
    }
    let plans: Vec<StagePlan> = pipeline.stages.iter()
        .map(|s| plan_stage(s, registry))
        .collect::<Result<Vec<_>>>()
        .unwrap_or_default();
    if plans.is_empty() { return (symbols.to_vec(), false); }
    let tf = pipeline.stages.first().map(|s| s.timeframe).unwrap_or(Timeframe::Daily);
    let mut all_symbols = symbols.to_vec();
    all_symbols.extend(["SH.000001", "SZ.399001", "BJ.899050"].iter().map(|s| s.to_string()));
    if let Some((results, deferred)) = try_run_batch_grouped(pipeline, registry, provider, symbols, &all_symbols, tf, from, to, &plans) {
        let survivors: Vec<String> = results.iter().filter(|r| r.eliminated_at.is_none()).map(|r| r.symbol.clone()).collect();
        return (survivors, !deferred.is_empty());
    }
    (symbols.to_vec(), false)
}

/// 检查表达式是否包含 StockId::Market 引用
fn expr_has_market_ref(e: &kline_dsl::Expr) -> bool {
    use kline_dsl::Expr;
    match e {
        Expr::CandleIs { stock: kline_dsl::StockId::Market, .. } => true,
        Expr::CrossUp { stock: kline_dsl::StockId::Market, .. } => true,
        Expr::CrossDown { stock: kline_dsl::StockId::Market, .. } => true,
        Expr::Path(p) if matches!(p.stock, kline_dsl::StockId::Market | kline_dsl::StockId::MarketNamed(_)) => true,
        Expr::Not(a) => expr_has_market_ref(a),
        Expr::And(a, b) | Expr::Or(a, b) | Expr::Gt(a, b) | Expr::Lt(a, b)
        | Expr::Gte(a, b) | Expr::Lte(a, b) | Expr::Eq(a, b) | Expr::Add(a, b)
        | Expr::Sub(a, b) | Expr::Mul(a, b) | Expr::Div(a, b) => {
            expr_has_market_ref(a) || expr_has_market_ref(b)
        }
        _ => false,
    }
}

fn parse_symbol_for_run(s: &str) -> Option<(i32, i32)> {
    let (mkt, code) = s.split_once('.')?;
    let m = match mkt { "SZ" => 0, "SH" => 1, "BJ" => 2, _ => return None };
    Some((m, code.parse().ok()?))
}

pub struct HashMapProvider<'a> {
    data: HashMap<String, DataFrame>,
    fallback: Option<&'a dyn DataProvider>,
    pub load_intraday: Option<&'a (dyn Fn(&str, NaiveDate) -> Option<DataFrame> + Sync)>,
}

impl<'a> HashMapProvider<'a> {
    pub fn new(data: HashMap<String, DataFrame>, fallback: Option<&'a dyn DataProvider>) -> Self {
        Self { data, fallback, load_intraday: None }
    }
    pub fn from_data(data: HashMap<String, DataFrame>) -> Self { Self { data, fallback: None, load_intraday: None } }
}

impl DataProvider for HashMapProvider<'_> {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame {
        if let Some(df) = self.data.get(symbol) {
            // 检查缓存是否覆盖请求的日期范围
            let dates = crate::extract_dates(df);
            if let (Some(first), Some(last)) = (dates.first(), dates.last()) {
                if *first <= from && *last >= to {
                    return df.clone().lazy();
                }
            }
            // 缓存不覆盖 → 回退到底层 provider
        }
        if let Some(fb) = &self.fallback {
            return fb.kline(symbol, tf, from, to);
        }
        DataFrame::default().lazy()
    }
    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame {
        if let Some(loader) = self.load_intraday {
            if let Some(df) = loader(symbol, date) {
                return df.lazy();
            }
        }
        DataFrame::default().lazy()
    }
    fn market_index(&self, symbol: &str) -> String {
        if let Some(fb) = &self.fallback {
            fb.market_index(symbol)
        } else {
            "sh000001".into()
        }
    }
}

pub fn run_pipeline_for_symbol(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    kline_provider: &dyn DataProvider,
    intraday_provider: &dyn DataProvider,
    symbol: &str,
    from: NaiveDate,
    to: NaiveDate,
    plans: &[StagePlan],
) -> Result<ScreenResult> {
    let mut passed_stages = Vec::new();
    let mut stage_results = Vec::new();

    for (stage_idx, stage) in pipeline.stages.iter().enumerate() {
        let result = run_stage(stage, registry, kline_provider, intraday_provider, symbol, from, to, &plans[stage_idx])?;
        if result.passed {
            passed_stages.push(stage.name.clone());
            stage_results.push(result);
        } else {
            let reason = result.failed_condition.clone();
            stage_results.push(result);
            return Ok(ScreenResult {
                symbol: symbol.to_string(),
                passed_stages,
                eliminated_at: Some(stage.name.clone()),
                eliminated_reason: reason,
                stage_results,
            });
        }
    }

    Ok(ScreenResult {
        symbol: symbol.to_string(),
        passed_stages,
        eliminated_at: None,
        eliminated_reason: None,
        stage_results,
    })
}

fn run_stage(
    stage: &Stage,
    registry: &ModuleRegistry,
    kline_provider: &dyn DataProvider,
    intraday_provider: &dyn DataProvider,
    symbol: &str,
    from: NaiveDate,
    to: NaiveDate,
    plan: &StagePlan,
) -> Result<StageResult> {
    let current = load_prepared_frame(stage, plan, registry, kline_provider, symbol, from, to)?;
    if current.requested_is_empty() {
        return Ok(stage_failure(&stage.name, symbol, "no_data"));
    }

    let market_frame = if stage.needs_market_data() {
        let market_symbol = kline_provider.market_index(symbol);
        Some(load_prepared_frame(
            stage,
            &plan,
            registry,
            kline_provider,
            &market_symbol,
            from,
            to,
        )?)
    } else {
        None
    };

    let mut extra_frames = Vec::with_capacity(stage.extra_stocks.len());
    for extra_symbol in &stage.extra_stocks {
        extra_frames.push((
            extra_symbol.clone(),
            load_prepared_frame(stage, &plan, registry, kline_provider, extra_symbol, from, to)?,
        ));
    }

    // 构建借出引用（不克隆，每个窗口复用）
    let extra_dfs: HashMap<String, &DataFrame> = extra_frames
        .iter()
        .map(|(name, frame)| (name.clone(), &frame.df))
        .collect();
    let extra_dates: HashMap<String, &DateIndex> = extra_frames
        .iter()
        .map(|(name, frame)| (name.clone(), &frame.dates))
        .collect();

    let intraday_cache = RefCell::new(IntradayCache::default());

    // ── 形态匹配（单点检查：start_date 位置是否匹配）───
    if let Some(pattern) = &stage.kline_pattern {
        let start_date = stage.start_date.unwrap_or(to);
        let windowsize = stage.windowsize.unwrap_or(WindowSize::Range { min: None, max: None });

        // 找到 start_date 所在行号（或最近的前一个交易日）
        let anchor = current
            .dates
            .row_of(start_date)
            .or_else(|| current.dates.dates.iter()
                .rposition(|d| *d < start_date))
            .unwrap_or(current.df.height());

        if anchor >= current.df.height() {
            return Ok(stage_failure(&stage.name, symbol, "no_data"));
        }

        // 单点匹配：只检查以 anchor 为窗口末尾的那一个位置
        let windows = if let Ok(partitions) =
            crate::matcher::polars_pattern::compile_partitions(&pattern.pattern, windowsize)
        {
            match match_pattern_via_polars(
                &current.df, &partitions, &pattern.pattern, anchor,
            ) {
                Ok(w) => w,
                Err(_) => {
                    let (expr, wlen) = crate::matcher::polars_pattern::try_compile(
                        &pattern.pattern, windowsize)?;
                    let mut w = fallback_polars_match(
                        &current.df, expr, wlen, anchor)?;
                    w.retain(|w| w.global_end == anchor + 1);
                    w
                }
            }
        } else {
            let open = crate::extract_f64_col(&current.df, "open");
            let close = crate::extract_f64_col(&current.df, "close");
            let mut w = match_pattern(&open, &close, &pattern.pattern, windowsize,
                0, current.requested_start, anchor + 1);
            w.retain(|w| w.global_end == anchor + 1);
            w
        };

        let mut all_matches: Vec<WindowMatch> = Vec::new();
        let mut first_points = HashMap::new();
        let mut first_marks = HashMap::new();
        let mut first_conditions = Vec::new();
        let mut first_failed: Option<StageResult> = None;

        for window in &windows {
            let mut ctx = build_ctx(
                &current, symbol, &market_frame, &extra_dfs, &extra_dates,
                window, registry, &intraday_cache, intraday_provider,
            );

            if let Some(result) = evaluate_window(stage, &mut ctx) {
                if result.passed {
                    let wm = WindowMatch {
                        window_start: window.global_start,
                        window_end: window.global_end,
                        resolved_points: result.resolved_points.clone(),
                        marks: result.marks.clone(),
                    };
                    if all_matches.is_empty() {
                        first_points = result.resolved_points;
                        first_marks = result.marks;
                        first_conditions = result.passed_conditions;
                    }
                    all_matches.push(wm);
                } else if first_failed.is_none() {
                    first_failed = Some(result);
                }
            }
        }

        if all_matches.is_empty() {
            if let Some(failed) = first_failed {
                Ok(failed)
            } else {
                Ok(stage_failure(&stage.name, symbol, "kline_pattern"))
            }
        } else {
            Ok(StageResult::first_match(
                stage.name.clone(), symbol.to_string(), first_points, first_marks, first_conditions, all_matches,
            ))
        }
    } else {
        // 无形态：单个窗口覆盖请求区间
        let window = MatchedWindow {
            global_start: current.requested_start,
            global_end: current.requested_end_exclusive,
            block_ranges: HashMap::new(),
        };

        let mut ctx = build_ctx(
            &current,
            symbol,
            &market_frame,
            &extra_dfs,
            &extra_dates,
            &window,
            registry,
            &intraday_cache,
            intraday_provider,
        );

        let eval_result = evaluate_window(stage, &mut ctx);
        match eval_result {
            Some(result) if result.passed => {
                let wm = WindowMatch {
                    window_start: window.global_start,
                    window_end: window.global_end,
                    resolved_points: result.resolved_points.clone(),
                    marks: result.marks.clone(),
                };
                Ok(StageResult::first_match(
                    stage.name.clone(), symbol.to_string(),
                    result.resolved_points, result.marks, result.passed_conditions,
                    vec![wm],
                ))
            }
            Some(result) => Ok(result),
            None => Err(anyhow!("no-pattern eval failed: {}", stage.name)),
        }
    }
}

/// 构建 EvalCtx（零克隆：extra_dfs / extra_dates 用借出引用）
fn build_ctx<'a>(
    current: &'a PreparedFrame,
    symbol: &'a str,
    market_frame: &'a Option<PreparedFrame>,
    extra_dfs: &'a HashMap<String, &'a DataFrame>,
    extra_dates: &'a HashMap<String, &'a DateIndex>,
    window: &'a MatchedWindow,
    registry: &'a ModuleRegistry,
    intraday_cache: &'a RefCell<IntradayCache>,
    provider: &'a dyn DataProvider,
) -> EvalCtx<'a> {
    EvalCtx::new(
        &current.df,
        &current.dates,
        symbol,
        market_frame.as_ref().map(|f| &f.df),
        market_frame.as_ref().map(|f| &f.dates),
        extra_dfs,
        extra_dates,
        window,
        registry,
        intraday_cache,
        provider,
    )
}

/// Evaluate vars, points, conditions, marks within a single window.
fn evaluate_window(stage: &Stage, ctx: &mut EvalCtx<'_>) -> Option<StageResult> {
    // Resolve points first — vars may reference points (e.g. Ap_pos, B_pos)
    resolve_points(&stage.points, ctx);

    // vars
    for var in &stage.vars {
        let value = eval_num(&var.expr, ctx, None);
        if value.is_nan() { return None; }
        ctx.vars.insert(var.name.clone(), value);
    }

    // conditions
    let mut passed_conditions = Vec::new();
    for (name, expr) in &stage.conditions {
        if eval_bool(expr, ctx, None) {
            passed_conditions.push(name.clone());
        } else {
            return Some(StageResult::failed(stage.name.clone(), ctx.symbol.to_string(), name.clone(), ctx.resolved_points.clone()));
        }
    }

    let marks = resolve_marks(&stage.marks, ctx);
    Some(StageResult::first_match(
        stage.name.clone(), ctx.symbol.to_string(),
        ctx.resolved_points.clone(),
        marks,
        passed_conditions,
        Vec::new(), // matches filled by caller
    ))
}

// ── Polars-native pattern match (inline collect on already-materialised frame) ─

/// Evaluate each partition expression at the anchor row.
/// For each match, compute block_ranges from the partition's size assignment.
fn match_pattern_via_polars(
    df: &DataFrame,
    partitions: &[crate::matcher::polars_pattern::PartitionExpr],
    blocks: &[kline_dsl::PatternBlock],
    anchor_row: usize,
) -> Result<Vec<MatchedWindow>> {
    let n = partitions.len();
    if n == 0 {
        return Ok(Vec::new());
    }

    // Add all partition expression columns at once
    let mut lf = df.clone().lazy();
    for (i, p) in partitions.iter().enumerate() {
        lf = lf.with_column(p.expr.clone().alias(format!("_p{i}")));
    }
    let df2 = match catch_unwind(std::panic::AssertUnwindSafe(|| lf.collect())) {
        Ok(Ok(df)) => df,
        Ok(Err(e)) => return Err(anyhow!("Polars pattern collect: {e}")),
        Err(_) => return Err(anyhow!("Polars pattern collect panicked")),
    };

    let mut windows = Vec::new();
    for (i, p) in partitions.iter().enumerate() {
        let col_name = format!("_p{i}");
        let mask = df2.column(&col_name)
            .context("missing partition column")?
            .bool()
            .context("partition column not bool")?;

        if mask.get(anchor_row).unwrap_or(false) {
            let wlen = p.window_len;
            windows.push(MatchedWindow {
                global_start: anchor_row.saturating_sub(wlen.saturating_sub(1)),
                global_end: anchor_row + 1,
                block_ranges: crate::matcher::polars_pattern::compute_block_ranges(
                    blocks, &p.sizes, anchor_row,
                ),
            });
        }
    }
    Ok(windows)
}

/// Fallback: single OR'd expression (for when per-partition approach fails).
fn fallback_polars_match(
    df: &DataFrame,
    expr: polars::prelude::Expr,
    window_len: Option<usize>,
    anchor_row: usize,
) -> Result<Vec<MatchedWindow>> {
    let df2 = match catch_unwind(std::panic::AssertUnwindSafe(|| {
        df.clone().lazy()
            .with_column(expr.alias("_patt"))
            .collect()
    })) {
        Ok(Ok(df)) => df,
        Ok(Err(e)) => return Err(anyhow!("Polars pattern collect: {e}")),
        Err(_) => return Err(anyhow!("Polars pattern collect panicked")),
    };
    let mask = df2.column("_patt")
        .context("missing _patt")?
        .bool()
        .context("_patt not bool")?;
    let wlen = window_len.unwrap_or(1);
    if mask.get(anchor_row).unwrap_or(false) {
        Ok(vec![MatchedWindow {
            global_start: anchor_row.saturating_sub(wlen.saturating_sub(1)),
            global_end: anchor_row + 1,
            block_ranges: HashMap::new(),
        }])
    } else {
        Ok(Vec::new())
    }
}

// ── 数据加载 ─────────────────────────────────────────────────

fn load_prepared_frame(
    stage: &Stage,
    plan: &StagePlan,
    _registry: &ModuleRegistry,
    provider: &dyn DataProvider,
    symbol: &str,
    from: NaiveDate,
    to: NaiveDate,
) -> Result<PreparedFrame> {
    let (expanded_from, expanded_to) = expand_date_range(from, to, stage.timeframe, plan);
    let mut lf = provider.kline(symbol, stage.timeframe, expanded_from, expanded_to);
    // 用预编译的指标表达式，不再重复编译
    for exprs in &plan.compiled_indicators {
        lf = lf.with_columns(exprs.clone());
    }

    let df = match catch_unwind(std::panic::AssertUnwindSafe(|| lf.collect())) {
        Ok(Ok(df)) => df,
        Ok(Err(e)) => {
            eprintln!("[load_prepared_frame] collect failed for {symbol}: {e}");
            DataFrame::empty()
        }
        Err(_) => {
            eprintln!("[load_prepared_frame] collect panicked for {symbol}");
            DataFrame::empty()
        }
    };
    let dates_vec = crate::extract_dates(&df);
    if df.height() > 0 && dates_vec.len() != df.height() {
        return Err(anyhow!(
            "missing or invalid date column for symbol={symbol}, stage={}",
            stage.name
        ));
    }
    let dates = DateIndex::new(dates_vec);

    let requested_start = dates
        .dates
        .iter()
        .position(|date| *date >= from)
        .unwrap_or(df.height());
    let requested_end_exclusive = dates
        .dates
        .iter()
        .rposition(|date| *date <= to)
        .map(|index| index + 1)
        .unwrap_or(requested_start);

    Ok(PreparedFrame {
        df,
        dates,
        requested_start,
        requested_end_exclusive,
    })
}

fn apply_prepare_stage(
    mut lf: polars::prelude::LazyFrame,
    prepare: &PrepareStage,
    registry: &ModuleRegistry,
) -> Result<polars::prelude::LazyFrame> {
    for call in &prepare.indicators {
        lf = apply_indicator_call(lf, call, registry)?;
    }
    Ok(lf)
}

fn apply_indicator_call(
    lf: polars::prelude::LazyFrame,
    call: &IndicatorCall,
    registry: &ModuleRegistry,
) -> Result<polars::prelude::LazyFrame> {
    let def = registry
        .indicators
        .get(call.module_id.as_str())
        .with_context(|| format!("indicator module not found: {}", call.module_id))?;
    let exprs = compile_mod(def, &call.params);
    Ok(lf.with_columns(exprs))
}

fn resolve_marks(
    marks: &[Mark],
    ctx: &EvalCtx<'_>,
) -> HashMap<String, (NaiveDate, Option<f64>)> {
    let mut resolved = HashMap::new();
    for mark in marks {
        let Some(row) = resolve_path_row(&mark.anchor, ctx, None) else { continue; };
        let Some(date) = ctx.dates.get_date(row) else { continue; };
        let value = mark.value.as_ref().map(|expr| {
            let v = eval_num(expr, ctx, None);
            if v.is_nan() { 0.0 } else { v }
        });
        resolved.insert(mark.name.clone(), (date, value));
    }
    resolved
}

fn stage_failure(stage_name: &str, symbol: &str, reason: &str) -> StageResult {
    StageResult::failed(stage_name.to_string(), symbol.to_string(), reason.to_string(), HashMap::new())
}

// ── 辅助 ─────────────────────────────────────────────────────

struct PreparedFrame {
    df: DataFrame,
    dates: DateIndex,
    requested_start: usize,
    requested_end_exclusive: usize,
}

impl PreparedFrame {
    fn requested_is_empty(&self) -> bool {
        self.requested_start >= self.requested_end_exclusive
    }
}

fn expand_date_range(
    from: NaiveDate,
    to: NaiveDate,
    timeframe: Timeframe,
    plan: &StagePlan,
) -> (NaiveDate, NaiveDate) {
    let back_days = calendar_padding_for_bars(timeframe, plan.lookback_bars);
    let ahead_days = calendar_padding_for_bars(timeframe, plan.lookahead_bars);

    let expanded_from = from
        .checked_sub_signed(Duration::days(back_days))
        .unwrap_or(from);
    let expanded_to = to
        .checked_add_signed(Duration::days(ahead_days))
        .unwrap_or(to);
    (expanded_from, expanded_to)
}

fn calendar_padding_for_bars(timeframe: Timeframe, bars: usize) -> i64 {
    if bars == 0 {
        return 0;
    }

    match timeframe {
        Timeframe::Daily => bars as i64 * 2 + 7,
        Timeframe::Weekly => bars as i64 * 7 + 14,
        Timeframe::Monthly => bars as i64 * 31 + 31,
        Timeframe::Minutes(step) => {
            let bars_per_day = (240u32 / step.max(1)).max(1) as usize;
            let trading_days = div_ceil(bars, bars_per_day);
            trading_days as i64 * 2 + 7
        }
    }
}

fn div_ceil(lhs: usize, rhs: usize) -> usize {
    if rhs == 0 {
        0
    } else {
        (lhs + rhs - 1) / rhs
    }
}
