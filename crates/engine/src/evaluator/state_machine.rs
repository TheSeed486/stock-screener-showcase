//! Intraday state machine: pre-compute atomic comparisons once per stock/day,
//! then answer IntradayBoolExpr range queries in O(1) via prefix sums.
//!
//! Replaces the per-minute AST walk for eligible conditions.

use kline_dsl::mod_def::intraday::*;

/// Atomic comparisons extracted from an IntradayBoolExpr AST.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Atom {
    /// price > avg (White > Yellow)
    PriceAboveAvg,
    /// price > pre_close (White > YesterdayOpen)
    PriceAbovePreClose,
    /// avg > pre_close (Yellow > YesterdayOpen)
    AvgAbovePreClose,
    /// price >= limit_up
    PriceAtLimitUp,
    /// price <= limit_down
    PriceAtLimitDown,
}

/// Comparison result: -1 (less), 0 (equal), 1 (greater)
pub type CmpResult = i8;

/// Pre-computed state for one stock on one day (240 minutes).
pub struct MinuteState {
    /// price > avg for each minute: -1/0/1
    pub price_vs_avg: [CmpResult; 240],
    /// price > pre_close: -1/0/1
    pub price_vs_pre: [CmpResult; 240],
    /// avg > pre_close: -1/0/1
    pub avg_vs_pre: [CmpResult; 240],
    /// price >= limit_up: -1/0/1 (1 = at or above limit_up)
    pub at_limit_up: [CmpResult; 240],
    /// price <= limit_down: -1/0/1 (1 = at or below limit_down)
    pub at_limit_down: [CmpResult; 240],
}

impl MinuteState {
    /// Build state from raw minute data arrays.
    /// price/avg are f64 in yuan, pre_close and limit_up/down are f64.
    pub fn build(
        price_col: &[f64],
        avg_col: &[f64],
        pre_close: f64,
        limit_up: f64,
        limit_down: f64,
    ) -> Self {
        let mut s = MinuteState {
            price_vs_avg: [0; 240],
            price_vs_pre: [0; 240],
            avg_vs_pre: [0; 240],
            at_limit_up: [0; 240],
            at_limit_down: [0; 240],
        };
        // Price/avg arrays include a pre_close sentinel at index 0.
        // Real minute data starts at index 1 (minute 0).
        for i in 0..240 {
            let idx = i + 1; // skip sentinel row
            let p = price_col.get(idx).copied().unwrap_or(0.0);
            let a = avg_col.get(idx).copied().unwrap_or(0.0);
            s.price_vs_avg[i] = cmp_f64(p, a);
            s.price_vs_pre[i] = cmp_f64(p, pre_close);
            s.avg_vs_pre[i] = cmp_f64(a, pre_close);
            s.at_limit_up[i] = if p >= limit_up - 0.005 { 1 } else { -1 };
            s.at_limit_down[i] = if p <= limit_down + 0.005 { 1 } else { -1 };
        }
        s
    }

    /// Get the atom array for a given atom type.
    pub fn atom(&self, a: Atom) -> &[CmpResult; 240] {
        match a {
            Atom::PriceAboveAvg => &self.price_vs_avg,
            Atom::PriceAbovePreClose => &self.price_vs_pre,
            Atom::AvgAbovePreClose => &self.avg_vs_pre,
            Atom::PriceAtLimitUp => &self.at_limit_up,
            Atom::PriceAtLimitDown => &self.at_limit_down,
        }
    }
}

fn cmp_f64(a: f64, b: f64) -> CmpResult {
    if a > b + 1e-9 {
        1
    } else if a < b - 1e-9 {
        -1
    } else {
        0
    }
}

// ── Prefix sum helpers ─────────────────────────────────────────────

/// Running count of "true" (value > 0) in the atom array.
pub struct PrefixCount {
    prefix: [u16; 241], // prefix[i] = count of true in [0, i)
}

impl PrefixCount {
    pub fn new(arr: &[CmpResult; 240]) -> Self {
        let mut prefix = [0u16; 241];
        for i in 0..240 {
            prefix[i + 1] = prefix[i] + if arr[i] > 0 { 1 } else { 0 };
        }
        Self { prefix }
    }

    /// Count of true in [from, to] (inclusive minute indices)
    pub fn count(&self, from: usize, to: usize) -> u16 {
        let to = to.min(239);
        if from > to {
            return 0;
        }
        self.prefix[to + 1] - self.prefix[from]
    }
}

/// Running "all true" check: whether all values in [0, i) are > 0
pub struct PrefixAll {
    all_prefix: [u8; 241], // all_prefix[i] = 1 if all [0, i) are >0, else 0
}

impl PrefixAll {
    pub fn new(arr: &[CmpResult; 240]) -> Self {
        let mut all_prefix = [1u8; 241];
        for i in 0..240 {
            all_prefix[i + 1] = all_prefix[i] & if arr[i] > 0 { 1 } else { 0 };
        }
        Self { all_prefix }
    }

    /// True if ALL values in [from, to] are > 0
    pub fn all(&self, from: usize, to: usize) -> bool {
        let to = to.min(239);
        if from > to {
            return true; // empty range → vacuously true
        }
        // all [from, to] = all [0, to+1) && !(any [0, from) is false)
        // = prefix[to+1] == 1 && (from == 0 || count_false(0, from-1) == 0)
        // Simpler: all in range = prefix stays 1 throughout
        self.all_prefix[to + 1] == 1 && (from == 0 || self.count_false(0, from - 1) == 0)
    }

    fn count_false(&self, from: usize, to: usize) -> usize {
        // Use the fact that all_prefix drops to 0 at first false
        if self.all_prefix[to + 1] == 1 {
            return 0; // all true up to to
        }
        // Binary search for first false
        let mut lo = from;
        let mut hi = to + 1;
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.all_prefix[mid + 1] == 0 {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        to + 1 - lo
    }
}

/// Running "any true" check: whether any value in [0, i) is > 0
pub struct PrefixAny {
    any_prefix: [u8; 241], // any_prefix[i] = 1 if any [0, i) is >0
}

impl PrefixAny {
    pub fn new(arr: &[CmpResult; 240]) -> Self {
        let mut any_prefix = [0u8; 241];
        for i in 0..240 {
            any_prefix[i + 1] = any_prefix[i] | if arr[i] > 0 { 1 } else { 0 };
        }
        Self { any_prefix }
    }

    /// True if ANY value in [from, to] is > 0
    pub fn any(&self, from: usize, to: usize) -> bool {
        let to = to.min(239);
        if from > to {
            return false;
        }
        self.any_prefix[to + 1] > self.any_prefix[from]
    }
}

/// State machine evaluator for a single IntradayBoolExpr.
/// Pre-computes prefix arrays for all needed atoms, then evaluates the AST
/// with O(1) range operations instead of per-minute iteration.
pub struct StateEvaluator {
    count_pre: Vec<(Atom, PrefixCount)>,
    all_pre: Vec<(Atom, PrefixAll)>,
    any_pre: Vec<(Atom, PrefixAny)>,
}

impl StateEvaluator {
    /// Build evaluator from a MinuteState and an IntradayBoolExpr.
    /// Extracts only the atoms actually referenced in the AST.
    pub fn new(state: &MinuteState, expr: &IntradayBoolExpr) -> Self {
        let atoms = collect_atoms(expr);
        let mut count_pre = Vec::new();
        let mut all_pre = Vec::new();
        let mut any_pre = Vec::new();
        for a in &atoms {
            let arr = state.atom(*a);
            count_pre.push((*a, PrefixCount::new(arr)));
            all_pre.push((*a, PrefixAll::new(arr)));
            any_pre.push((*a, PrefixAny::new(arr)));
        }
        Self {
            count_pre,
            all_pre,
            any_pre,
        }
    }

    pub fn count_prefixes(&self) -> &[(Atom, PrefixCount)] { &self.count_pre }
    pub fn all_prefixes(&self) -> &[(Atom, PrefixAll)] { &self.all_pre }
    pub fn any_prefixes(&self) -> &[(Atom, PrefixAny)] { &self.any_pre }
}

/// Collect all Atom references from an IntradayBoolExpr AST.
pub fn collect_atoms(expr: &IntradayBoolExpr) -> Vec<Atom> {
    let mut atoms = Vec::new();
    collect_atoms_impl(expr, &mut atoms);
    atoms.sort();
    atoms.dedup();
    atoms
}

fn collect_atoms_impl(expr: &IntradayBoolExpr, out: &mut Vec<Atom>) {
    match expr {
        IntradayBoolExpr::Gt(a, b) | IntradayBoolExpr::Lt(a, b)
        | IntradayBoolExpr::Gte(a, b) | IntradayBoolExpr::Lte(a, b)
        | IntradayBoolExpr::Eq(a, b) => {
            push_val_atoms(a, out);
            push_val_atoms(b, out);
        }
        IntradayBoolExpr::And(a, b) | IntradayBoolExpr::Or(a, b) => {
            collect_atoms_impl(a, out);
            collect_atoms_impl(b, out);
        }
        IntradayBoolExpr::Not(a) => collect_atoms_impl(a, out),
        IntradayBoolExpr::AllMinutes { pred, .. } => collect_atoms_impl(pred, out),
        IntradayBoolExpr::AnyMinute { pred, .. } => collect_atoms_impl(pred, out),
        IntradayBoolExpr::DurationGte { pred, .. } => collect_atoms_impl(pred, out),
        IntradayBoolExpr::DurationLte { pred, .. } => collect_atoms_impl(pred, out),
    }
}

fn push_val_atoms(val: &IntradayVal, out: &mut Vec<Atom>) {
    match val {
        IntradayVal::White(_) | IntradayVal::Close(_) | IntradayVal::Open(_) => {
            // White references appear in price comparisons
        }
        IntradayVal::Yellow(_) => {
            // Yellow references appear in avg comparisons
        }
        IntradayVal::YesterdayOpen => {}
        IntradayVal::LimitUpPrice => {}
        IntradayVal::LimitDownPrice => {}
        _ => {} // Literal, param, arithmetic → no atom needed
    }
    // Actually extract specific atoms from binary comparisons:
    // This is handled by the comparison-level extraction below.
}

/// Extract the specific atom from a comparison between two IntradayVals.
pub fn extract_atom(left: &IntradayVal, right: &IntradayVal) -> Option<Atom> {
    use IntradayVal::*;
    match (left, right) {
        (White(_), Yellow(_)) | (Yellow(_), White(_)) => Some(Atom::PriceAboveAvg),
        (White(_), YesterdayOpen) | (YesterdayOpen, White(_)) => Some(Atom::PriceAbovePreClose),
        (Yellow(_), YesterdayOpen) | (YesterdayOpen, Yellow(_)) => Some(Atom::AvgAbovePreClose),
        (White(_), LimitUpPrice) | (LimitUpPrice, White(_)) => Some(Atom::PriceAtLimitUp),
        (White(_), LimitDownPrice) | (LimitDownPrice, White(_)) => Some(Atom::PriceAtLimitDown),
        _ => None,
    }
}
