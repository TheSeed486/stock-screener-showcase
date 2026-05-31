// Expr compiler — transforms ExprNode into serde-compatible JSON.
// ExprNode.toJson() already produces the correct format,
// so this file mainly handles PointDef compilation.

import '../models/expr_node.dart';
import '../models/stage_model.dart';

/// Compile an ExprNode to its serde-compatible JSON map.
Map<String, dynamic> compileExpr(ExprNode expr) => expr.toJson();

/// Compile a PointDefModel to the JSON format expected by Rust PointDef.
Map<String, dynamic> compilePointDef(PointDefModel def) => def.toJson();
