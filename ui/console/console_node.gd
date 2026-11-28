class_name NelvarConsoleNode
extends RefCounted
## One step of a console command, like a node of a command tree: a fixed word
## ("give") or an argument ("<amount>"). A command is a path from the root
## word down its children; a node with a handler may end the command there,
## so a handler on a node that also has children makes the rest optional.
##
## The tree gives both the parsing and the hints: the children of the last
## matched node are what may come next.

enum Kind { LITERAL, INT, FLOAT, CHOICE }

var kind := Kind.LITERAL
## The word itself for a literal, the argument name otherwise.
var name := ""
## Short explanation shown next to the suggestion.
var hint := ""
var children: Array[NelvarConsoleNode] = []
## func(args: Dictionary) -> void; args maps argument names to their values.
var handler := Callable()
## CHOICE: func() -> Array of {"text": String, "hint": String}.
var source := Callable()
var min_value := -INF
var max_value := INF


static func literal(word: String, explanation: String = "") -> NelvarConsoleNode:
	var node := NelvarConsoleNode.new()
	node.name = word
	node.hint = explanation
	return node


static func integer(arg_name: String, low: float = -INF, high: float = INF) -> NelvarConsoleNode:
	var node := _argument(Kind.INT, arg_name)
	node.min_value = low
	node.max_value = high
	return node


static func number(arg_name: String, low: float = -INF, high: float = INF) -> NelvarConsoleNode:
	var node := _argument(Kind.FLOAT, arg_name)
	node.min_value = low
	node.max_value = high
	return node


## An argument picked from a list that may change while the game runs
## (mutation ids, enemy kinds...).
static func choice(arg_name: String, options: Callable) -> NelvarConsoleNode:
	var node := _argument(Kind.CHOICE, arg_name)
	node.source = options
	return node


static func _argument(node_kind: Kind, arg_name: String) -> NelvarConsoleNode:
	var node := NelvarConsoleNode.new()
	node.kind = node_kind
	node.name = arg_name
	return node


## Adds children; returns self so trees can be written in one expression.
func then(child: NelvarConsoleNode, more: Array = []) -> NelvarConsoleNode:
	children.append(child)
	for extra: NelvarConsoleNode in more:
		children.append(extra)
	return self


## The command may end at this node and runs `callable`.
func runs(callable: Callable) -> NelvarConsoleNode:
	handler = callable
	return self


## Sets the hint; returns self.
func described(text: String) -> NelvarConsoleNode:
	hint = text
	return self


func is_literal() -> bool:
	return kind == Kind.LITERAL


## How the node reads in hints: "give", "<amount>".
func label() -> String:
	return name if is_literal() else "<%s>" % name


## Whether `token` fits this node.
func matches(token: String) -> bool:
	return error_for(token).is_empty()


## Why `token` does not fit (empty when it does).
func error_for(token: String) -> String:
	match kind:
		Kind.LITERAL:
			return "" if token.to_lower() == name.to_lower() else "ожидалось «%s»" % name
		Kind.INT:
			if not token.is_valid_int():
				return "«%s» — не целое число" % token
			return _range_error(token.to_int())
		Kind.FLOAT:
			if not token.is_valid_float():
				return "«%s» — не число" % token
			return _range_error(token.to_float())
		Kind.CHOICE:
			for option in options():
				if String(option["text"]).to_lower() == token.to_lower():
					return ""
			return "нет такого: «%s»" % token
	return ""


## The value a matching token gives the handler.
func parse(token: String) -> Variant:
	match kind:
		Kind.INT:
			return token.to_int()
		Kind.FLOAT:
			return token.to_float()
		Kind.CHOICE:
			for option in options():
				if String(option["text"]).to_lower() == token.to_lower():
					return String(option["text"])
	return token.to_lower()


## What can be typed here: {"text", "hint"}. Numbers have none.
func options() -> Array:
	match kind:
		Kind.LITERAL:
			return [{"text": name, "hint": hint}]
		Kind.CHOICE:
			return source.call() if source.is_valid() else []
	return []


func _range_error(value: float) -> String:
	if value < min_value:
		return "не меньше %s" % _format(min_value)
	if value > max_value:
		return "не больше %s" % _format(max_value)
	return ""


static func _format(value: float) -> String:
	return ("%.2f" % value).rstrip("0").trim_suffix(".")
