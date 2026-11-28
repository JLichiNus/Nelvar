class_name NelvarCommandTree
extends RefCounted
## The console's commands without the look: parses a typed line, runs it and
## says what may be typed next (the hints under the input line).
##
## Commands are trees of NelvarConsoleNode, one per first word. A line is
## words split by spaces; a leading "/" is optional.

## A line of console output. kind: INFO, GOOD or ERROR.
signal printed(text: String, kind: int)

enum Output { INFO, GOOD, ERROR, ECHO }

var _roots: Array[NelvarConsoleNode] = []


func add(root: NelvarConsoleNode) -> void:
	_roots.append(root)


## Drops every command (their handlers hold whoever made them, so the trees
## must go before the game quits).
func clear() -> void:
	_roots.clear()


func roots() -> Array[NelvarConsoleNode]:
	return _roots.duplicate()


func find_root(word: String) -> NelvarConsoleNode:
	for root in _roots:
		if root.name.to_lower() == word.to_lower():
			return root
	return null


func info(text: String) -> void:
	printed.emit(text, Output.INFO)


func good(text: String) -> void:
	printed.emit(text, Output.GOOD)


func error(text: String) -> void:
	printed.emit(text, Output.ERROR)


## Parses and runs `line`. Returns the error text, empty when it ran.
func execute(line: String) -> String:
	var words := _words(_strip(line))
	if words.is_empty():
		return ""
	var parsed := _walk(words)
	if not parsed["error"].is_empty():
		error(parsed["error"])
		return parsed["error"]
	var node: NelvarConsoleNode = parsed["node"]
	if not node.handler.is_valid():
		var message := "Не хватает аргумента: %s" % _labels(node.children)
		error(message)
		return message
	node.handler.call(parsed["args"])
	return ""


## What may come at the end of `text` (the text before the caret):
## - start: index in `text` where the word being typed begins;
## - prefix: that word so far;
## - candidates: [{"text", "hint", "more"}] that fit the prefix;
## - expected: labels of the arguments that may come here ("<amount>");
## - error: why the words before it do not parse (empty when they do).
func suggest(text: String) -> Dictionary:
	var offset := 1 if text.begins_with("/") else 0
	var body := text.substr(offset)
	var parts := body.split(" ")
	var prefix: String = parts[parts.size() - 1]
	var done: Array[String] = []
	for i in parts.size() - 1:
		if not parts[i].is_empty():
			done.append(parts[i])
	var result := {
		"start": text.length() - prefix.length(),
		"prefix": prefix,
		"candidates": [],
		"expected": PackedStringArray(),
		"error": "",
	}
	var next: Array[NelvarConsoleNode] = _roots
	if not done.is_empty():
		var parsed := _walk(done)
		if not parsed["error"].is_empty():
			result["error"] = parsed["error"]
			return result
		next = (parsed["node"] as NelvarConsoleNode).children
	var lower := prefix.to_lower()
	# Words that start with the prefix first, then those found by their hint
	# ("лёг" finds light_body by its title).
	var by_word: Array = []
	var by_hint: Array = []
	for child in next:
		if not child.is_literal():
			result["expected"].append(child.label())
		for option in child.options():
			var option_text := String(option["text"])
			var hint := String(option.get("hint", ""))
			# more: something may follow this word (Tab adds a space after it).
			var candidate := {"text": option_text, "hint": hint, "more": not child.children.is_empty()}
			if option_text.to_lower().begins_with(lower):
				by_word.append(candidate)
			elif not lower.is_empty() and hint.to_lower().contains(lower):
				by_hint.append(candidate)
	result["candidates"] = by_word + by_hint
	return result


## Every complete form of `root`: [{"usage": "/hp add <amount>", "hint"}].
func usages(root: NelvarConsoleNode) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_usages(root, "/" + root.label(), root.hint, result)
	return result


func _collect_usages(node: NelvarConsoleNode, path: String, hint: String,
		result: Array[Dictionary]) -> void:
	if node.handler.is_valid():
		result.append({"usage": path, "hint": hint})
	for child in node.children:
		var child_hint := child.hint if not child.hint.is_empty() else hint
		_collect_usages(child, path + " " + child.label(), child_hint, result)


# Follows `words` down the trees: {"node", "args", "error"}.
func _walk(words: Array[String]) -> Dictionary:
	var root := find_root(words[0])
	if root == null:
		return {"node": null, "args": {}, "error": "Неизвестная команда: %s" % words[0]}
	var node := root
	var args := {}
	for i in range(1, words.size()):
		var word := words[i]
		var found: NelvarConsoleNode = null
		# Fixed words before arguments: "all" wins over a mutation named so.
		for child in node.children:
			if child.is_literal() and child.matches(word):
				found = child
				break
		if found == null:
			for child in node.children:
				if not child.is_literal() and child.matches(word):
					found = child
					break
		if found == null:
			return {"node": node, "args": args, "error": _mismatch(node, word)}
		if not found.is_literal():
			args[found.name] = found.parse(word)
		node = found
	return {"node": node, "args": args, "error": ""}


func _mismatch(node: NelvarConsoleNode, word: String) -> String:
	if node.children.is_empty():
		return "Лишний аргумент: %s" % word
	if node.children.size() == 1:
		return "%s: %s" % [node.children[0].label(), node.children[0].error_for(word)]
	return "Неверный аргумент «%s», ожидалось: %s" % [word, _labels(node.children)]


static func _labels(nodes: Array[NelvarConsoleNode]) -> String:
	var labels := PackedStringArray()
	for node in nodes:
		labels.append(node.label())
	return " | ".join(labels)


static func _strip(line: String) -> String:
	var text := line.strip_edges()
	return text.substr(1) if text.begins_with("/") else text


static func _words(text: String) -> Array[String]:
	var words: Array[String] = []
	for part in text.split(" ", false):
		words.append(part)
	return words
