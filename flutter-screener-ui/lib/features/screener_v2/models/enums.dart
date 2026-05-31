// Enums mirroring crates/dsl/src/types.rs — serde-compatible names.

enum TimeframeEnum {
  daily,
  weekly,
  monthly;

  String get label {
    switch (this) {
      case TimeframeEnum.daily: return '日线';
      case TimeframeEnum.weekly: return '周线';
      case TimeframeEnum.monthly: return '月线';
    }
  }

  String toJson() {
    switch (this) {
      case TimeframeEnum.daily: return 'Daily';
      case TimeframeEnum.weekly: return 'Weekly';
      case TimeframeEnum.monthly: return 'Monthly';
    }
  }

  static TimeframeEnum fromJson(String s) {
    switch (s) {
      case 'Daily': return TimeframeEnum.daily;
      case 'Weekly': return TimeframeEnum.weekly;
      case 'Monthly': return TimeframeEnum.monthly;
      default: return TimeframeEnum.daily;
    }
  }
}

enum AggFuncEnum {
  max, min, mean, sum, first, last, stdDev;

  String toJson() {
    switch (this) {
      case AggFuncEnum.max: return 'Max';
      case AggFuncEnum.min: return 'Min';
      case AggFuncEnum.mean: return 'Mean';
      case AggFuncEnum.sum: return 'Sum';
      case AggFuncEnum.first: return 'First';
      case AggFuncEnum.last: return 'Last';
      case AggFuncEnum.stdDev: return 'StdDev';
    }
  }

  String get label {
    switch (this) {
      case AggFuncEnum.max: return '最大值';
      case AggFuncEnum.min: return '最小值';
      case AggFuncEnum.mean: return '均值';
      case AggFuncEnum.sum: return '求和';
      case AggFuncEnum.first: return '第一个';
      case AggFuncEnum.last: return '最后一个';
      case AggFuncEnum.stdDev: return '标准差';
    }
  }

  static AggFuncEnum fromJson(String s) {
    return AggFuncEnum.values.firstWhere(
      (e) => e.toJson() == s,
      orElse: () => AggFuncEnum.max,
    );
  }
}

enum CmpOpEnum {
  gt, gte, lt, lte, eq;

  String toJson() {
    switch (this) {
      case CmpOpEnum.gt: return 'Gt';
      case CmpOpEnum.gte: return 'Gte';
      case CmpOpEnum.lt: return 'Lt';
      case CmpOpEnum.lte: return 'Lte';
      case CmpOpEnum.eq: return 'Eq';
    }
  }

  String get symbol {
    switch (this) {
      case CmpOpEnum.gt: return '>';
      case CmpOpEnum.gte: return '>=';
      case CmpOpEnum.lt: return '<';
      case CmpOpEnum.lte: return '<=';
      case CmpOpEnum.eq: return '==';
    }
  }

  String get label {
    switch (this) {
      case CmpOpEnum.gt: return '大于';
      case CmpOpEnum.gte: return '大于等于';
      case CmpOpEnum.lt: return '小于';
      case CmpOpEnum.lte: return '小于等于';
      case CmpOpEnum.eq: return '等于';
    }
  }

  static CmpOpEnum fromJson(String s) {
    return CmpOpEnum.values.firstWhere(
      (e) => e.toJson() == s,
      orElse: () => CmpOpEnum.gt,
    );
  }
}

enum MonotoneDirEnum {
  strictInc, strictDec, nonDec, nonInc;

  String toJson() {
    switch (this) {
      case MonotoneDirEnum.strictInc: return 'StrictInc';
      case MonotoneDirEnum.strictDec: return 'StrictDec';
      case MonotoneDirEnum.nonDec: return 'NonDec';
      case MonotoneDirEnum.nonInc: return 'NonInc';
    }
  }

  String get label {
    switch (this) {
      case MonotoneDirEnum.strictInc: return '严格递增';
      case MonotoneDirEnum.strictDec: return '严格递减';
      case MonotoneDirEnum.nonDec: return '非递减';
      case MonotoneDirEnum.nonInc: return '非递增';
    }
  }

  static MonotoneDirEnum fromJson(String s) {
    return MonotoneDirEnum.values.firstWhere(
      (e) => e.toJson() == s,
      orElse: () => MonotoneDirEnum.strictInc,
    );
  }
}

enum CandleTypeEnum {
  up, down, neutral, doji, any;

  String toJson() {
    switch (this) {
      case CandleTypeEnum.up: return 'Up';
      case CandleTypeEnum.down: return 'Down';
      case CandleTypeEnum.neutral: return 'Neutral';
      case CandleTypeEnum.doji: return 'Doji';
      case CandleTypeEnum.any: return 'Any';
    }
  }

  String get label {
    switch (this) {
      case CandleTypeEnum.up: return '阳线';
      case CandleTypeEnum.down: return '阴线';
      case CandleTypeEnum.neutral: return '中性';
      case CandleTypeEnum.doji: return '十字星';
      case CandleTypeEnum.any: return '任意';
    }
  }

  static CandleTypeEnum fromJson(String s) {
    return CandleTypeEnum.values.firstWhere(
      (e) => e.toJson() == s,
      orElse: () => CandleTypeEnum.any,
    );
  }
}

enum PointSelectKind {
  first, last, nth, nthFromEnd;

  String get label {
    switch (this) {
      case PointSelectKind.first: return '第一个';
      case PointSelectKind.last: return '最后一个';
      case PointSelectKind.nth: return '第N个';
      case PointSelectKind.nthFromEnd: return '倒数第N个';
    }
  }
}

enum FieldNameEnum {
  open, high, low, close, volume, amount, pctChange, amplitude, turnover;

  String get label {
    switch (this) {
      case FieldNameEnum.open: return '开盘价';
      case FieldNameEnum.high: return '最高价';
      case FieldNameEnum.low: return '最低价';
      case FieldNameEnum.close: return '收盘价';
      case FieldNameEnum.volume: return '成交量';
      case FieldNameEnum.amount: return '成交额';
      case FieldNameEnum.pctChange: return '涨跌幅';
      case FieldNameEnum.amplitude: return '振幅';
      case FieldNameEnum.turnover: return '换手率';
    }
  }

  String get jsonKey {
    switch (this) {
      case FieldNameEnum.pctChange: return 'pct_change';
      default: return name;
    }
  }
}
