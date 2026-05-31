use kline_dsl::pipeline::{NamedPoint, PointDef, PointSelect};

use crate::evaluator::{
    ctx::EvalCtx,
    expr::{eval_bool, resolve_range_rows},
};

pub fn resolve_points(points: &[NamedPoint], ctx: &mut EvalCtx<'_>) {
    for np in points {
        let row = resolve_one_point(&np.def, ctx);
        ctx.resolved_points.insert(np.name.clone(), row);
    }
}

fn resolve_one_point(def: &PointDef, ctx: &EvalCtx<'_>) -> Option<usize> {
    match def {
        PointDef::BlockStart(name) => ctx.window.block_start(name),
        PointDef::BlockEnd(name) => ctx.window.block_last(name),

        PointDef::Offset { from, delta } => {
            let base = ctx.resolved_points.get(from.as_str()).copied().flatten()?;
            let row = base as i64 + delta;
            if row >= 0 && (row as usize) < ctx.df.height() {
                Some(row as usize)
            } else {
                None
            }
        }

        PointDef::Where { stock, from, to, pred, select } => {
            let (start, end) = resolve_range_rows(stock, from, to, ctx)?;
            let candidates: Vec<usize> = (start..=end)
                .filter(|&row| eval_bool(pred, ctx, Some(row)))
                .collect();
            if candidates.is_empty() { return None; }
            match select {
                PointSelect::First => candidates.first().copied(),
                PointSelect::Last => candidates.last().copied(),
                PointSelect::Nth(n) => candidates.get(*n).copied(),
                PointSelect::NthFromEnd(n) => {
                    candidates.len().checked_sub(n + 1).and_then(|i| candidates.get(i).copied())
                }
            }
        }
    }
}
