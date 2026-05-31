// PathRef mirrors crates/dsl/src/expr.rs PathExpr, StockId, Anchor.

sealed class StockRef {
  const StockRef();
  Map<String, dynamic> toJson();
  String get stockType; // 'current', 'market', 'named', 'marketNamed'

  static const StockRef current = _CurrentStock();
  static const StockRef market = _MarketStock();
  static StockRef named(String ticker) => _NamedStock(ticker);
  static StockRef marketNamed(String ticker) => _MarketNamedStock(ticker);

  static StockRef fromJson(Map<String, dynamic> json) {
    final t = json['t'] as String;
    final v = json['v'];
    switch (t) {
      case 'Current': return current;
      case 'Market': return market;
      case 'Named': return named(v as String);
      case 'MarketNamed': return marketNamed(v as String);
      default: return current;
    }
  }

  String get displayLabel;
}

class _CurrentStock extends StockRef {
  const _CurrentStock();
  @override String get stockType => 'current';
  @override Map<String, dynamic> toJson() => {'t': 'Current'};
  @override String get displayLabel => '当前股票';
}

class _MarketStock extends StockRef {
  const _MarketStock();
  @override String get stockType => 'market';
  @override Map<String, dynamic> toJson() => {'t': 'Market'};
  @override String get displayLabel => '大盘指数';
}

class _NamedStock extends StockRef {
  final String ticker;
  const _NamedStock(this.ticker);
  @override String get stockType => 'named';
  @override Map<String, dynamic> toJson() => {'t': 'Named', 'v': ticker};
  @override String get displayLabel => ticker;
}

class _MarketNamedStock extends StockRef {
  final String ticker;
  const _MarketNamedStock(this.ticker);
  @override String get stockType => 'marketNamed';
  @override Map<String, dynamic> toJson() => {'t': 'MarketNamed', 'v': ticker};
  @override String get displayLabel => '大盘:$ticker';
}

// ── Anchor ──────────────────────────────────────────────────

sealed class AnchorKind {
  const AnchorKind();
  Map<String, dynamic> toJson();
  String get displayLabel;
  String get anchorType; // 'windowEnd', 'windowStart', 'eachBar', 'point'

  static const AnchorKind windowEnd = WindowEndAnchor();
  static const AnchorKind windowStart = WindowStartAnchor();
  static const AnchorKind eachBar = EachBarAnchor();
  static AnchorKind point(String name) => PointAnchor(name);

  static AnchorKind fromJson(Map<String, dynamic> json) {
    final t = json['t'] as String;
    final v = json['v'];
    switch (t) {
      case 'WindowEnd': return windowEnd;
      case 'WindowStart': return windowStart;
      case 'EachBar': return eachBar;
      case 'Point': return point(v as String);
      default: return windowEnd;
    }
  }
}

class PointAnchor extends AnchorKind {
  final String name;
  const PointAnchor(this.name);
  @override String get anchorType => 'point';
  @override Map<String, dynamic> toJson() => {'t': 'Point', 'v': name};
  @override String get displayLabel => '点:$name';
}

class WindowStartAnchor extends AnchorKind {
  const WindowStartAnchor();
  @override String get anchorType => 'windowStart';
  @override Map<String, dynamic> toJson() => {'t': 'WindowStart'};
  @override String get displayLabel => '窗口起点';
}

class WindowEndAnchor extends AnchorKind {
  const WindowEndAnchor();
  @override String get anchorType => 'windowEnd';
  @override Map<String, dynamic> toJson() => {'t': 'WindowEnd'};
  @override String get displayLabel => '窗口终点(最新)';
}

class EachBarAnchor extends AnchorKind {
  const EachBarAnchor();
  @override String get anchorType => 'eachBar';
  @override Map<String, dynamic> toJson() => {'t': 'EachBar'};
  @override String get displayLabel => '逐根遍历';
}

// ── PathRef ─────────────────────────────────────────────────

class PathRef {
  final StockRef stock;
  final AnchorKind anchor;
  final int offset;
  final String? field;

  const PathRef({
    this.stock = StockRef.current,
    this.anchor = AnchorKind.windowEnd,
    this.offset = 0,
    this.field,
  });

  PathRef copyWith({
    StockRef? stock,
    AnchorKind? anchor,
    int? offset,
    String? field,
    bool clearField = false,
  }) => PathRef(
    stock: stock ?? this.stock,
    anchor: anchor ?? this.anchor,
    offset: offset ?? this.offset,
    field: clearField ? null : (field ?? this.field),
  );

  Map<String, dynamic> toJson() => {
    'stock': stock.toJson(),
    'anchor': anchor.toJson(),
    'offset': offset,
    'field': field,
  };

  factory PathRef.fromJson(Map<String, dynamic> json) => PathRef(
    stock: StockRef.fromJson(Map<String, dynamic>.from(json['stock'] as Map)),
    anchor: AnchorKind.fromJson(Map<String, dynamic>.from(json['anchor'] as Map)),
    offset: (json['offset'] as num?)?.toInt() ?? 0,
    field: json['field'] as String?,
  );

  String get displayLabel {
    final parts = <String>[stock.displayLabel];
    parts.add(anchor.displayLabel);
    if (offset != 0) parts.add(offset > 0 ? '+$offset' : '$offset');
    if (field != null) parts.add(field!);
    return parts.join('.');
  }

  // Convenience constructors
  static PathRef close({int offset = 0}) =>
      PathRef(field: 'close', offset: offset);
  static PathRef open({int offset = 0}) =>
      PathRef(field: 'open', offset: offset);
  static PathRef high({int offset = 0}) =>
      PathRef(field: 'high', offset: offset);
  static PathRef low({int offset = 0}) =>
      PathRef(field: 'low', offset: offset);
  static PathRef volume({int offset = 0}) =>
      PathRef(field: 'volume', offset: offset);
  static PathRef each({String? field}) =>
      PathRef(anchor: AnchorKind.eachBar, field: field);
}
