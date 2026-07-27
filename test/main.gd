extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# print(FWBinaryParser.MAGIC_NUMBER)
	# print(FWSaveTypes.Result.failure(2000 as FWSaveTypes.Error))
	# var bytes = FileAccess.get_file_as_bytes("res://test/test.bin")
	# var parser = FWBinaryParser.new("a", "b", "c")
	# var data = parser.decode(bytes).value as FWSaveTypes.FileData
	# print(data.header.version)
	# print(data.header.file_size)
	# print(data.header.toc_count)
	# print(data.header.flags)
	# print(data.header.game_literal)
	# print(data.header.game_version)
	# print(data.header.godot_version)
	# print(data.header.toc_checksum)
	# print(data.header.header_checksum)
	var data: FWSaveTypes.FileData = FWSaveTypes.FileData.new()
	data.toc[&"key1"] = FWSaveTypes.TocEntry.new()
	data.payloads[&"key1"] = PackedByteArray([1,2,3,4,5])

	var parser := FWBinaryParser.new("MyGame1", "1.0.0", "godot4.5.1")
	var bytes := parser.encode(data).value as PackedByteArray
	FileAccess.open("res://test/out.fwsv", FileAccess.WRITE).store_buffer(bytes)

	print(bytes)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
