
class_name FWBinaryParser
extends RefCounted

const CURRENT_VERSION: int = 1

const MAGIC_NUMBER: int = 0x56535746	# FWSV

const GAME_LITERAL_SIZE = 32
const GAME_VERSION_SIZE = 32
const GODOT_VERSION_SIZE = 32

var game_literal: StringName
var game_version: StringName
var godot_version: StringName

func _init(game_literal: StringName, game_version: StringName, godot_version: StringName):
	self.game_literal = game_literal.left(GAME_LITERAL_SIZE)
	self.game_version = game_version.left(GAME_VERSION_SIZE)
	self.godot_version = godot_version.left(GODOT_VERSION_SIZE)

func decode(bytes: PackedByteArray) -> FWSaveTypes.Result:
	var file_data := FWSaveTypes.FileData.new()
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = bytes

	if stream.get_size() < 8:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.FILE_SIZE_TOO_SMALL)
	
	var magic_number := stream.get_u32()
	if magic_number != MAGIC_NUMBER:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.INVALID_FILE_TYPE)
	file_data.header.magic_number = MAGIC_NUMBER
	
	var header_version := stream.get_u32()
	file_data.header.version = header_version
	match header_version:
		1:
			return _decode_v1(stream, file_data)
		_:
			return FWSaveTypes.Result.failure(FWSaveTypes.Error.UNKNOWN_HEADER_VERSION)

func _decode_v1(stream: StreamPeerBuffer, file_data: FWSaveTypes.FileData) -> FWSaveTypes.Result:
	var res: FWSaveTypes.Result = _decode_v1_header(stream, file_data)
	if !res.is_ok():
		return res
		
	res = _decode_v1_toc(stream, file_data)
	if !res.is_ok():
		return res
	
	return FWSaveTypes.Result.success(file_data)

func _decode_v1_header(stream: StreamPeerBuffer, file_data: FWSaveTypes.FileData) -> FWSaveTypes.Result:
	if stream.get_size() < 256:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.HEADER_NOT_PRESENT)
	
	stream.seek(224)
	var header_checksum_res = stream.get_data(32)
	if header_checksum_res[0] != OK:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.CORRUPTED_FILE)
	file_data.header.header_checksum = header_checksum_res[1]
	
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(stream.data_array.slice(0, 224))
	if ctx.finish() != file_data.header.header_checksum:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.INVALID_HEADER_CHECKSUM)
	
	stream.seek(8)
	file_data.header.file_size = stream.get_u32()
	file_data.header.toc_count = stream.get_u16()
	file_data.header.flags = stream.get_u16()
	
	file_data.header.game_literal = stream.get_string(32)
	if game_literal != self.game_literal:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.DIFFERENT_GAME_LITERAL)
	stream.seek(48)
	
	file_data.header.game_version = stream.get_string(32)
	stream.seek(80)
	
	# Godot Version is currently skipped
	file_data.header.godot_version = stream.get_string(32)
	stream.seek(112)
	
	stream.seek(192)
	
	var toc_checksum_res = stream.get_data(32)
	if toc_checksum_res[0] != OK:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.CORRUPTED_FILE)
	file_data.header.toc_checksum = toc_checksum_res[1]
	
	return FWSaveTypes.Result.success(file_data)

func _decode_v1_toc(stream: StreamPeerBuffer, file_data: FWSaveTypes.FileData) -> FWSaveTypes.Result:
	var toc_end := 256 + 80 * file_data.header.toc_count
	if stream.get_size() < toc_end:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.TOC_ENTRIES_NOT_PRESENT)
	
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(stream.data_array.slice(256, toc_end))
	if ctx.finish() != file_data.header.toc_checksum:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.INVALID_TOC_CHECKSUM)
	
	stream.seek(256)
	for i in range(file_data.header.toc_count):
		var toc_entry: FWSaveTypes.TocEntry = FWSaveTypes.TocEntry.new()
		
		toc_entry.key = stream.get_string(32)
		stream.seek(256 + 80 * i + 32)
		
		toc_entry.payload_offset = stream.get_u32()
		toc_entry.payload_disk_size = stream.get_u32()
		toc_entry.payload_uncompressed_size = stream.get_u32()
		toc_entry.encoding = stream.get_u16()
		
		var payload_checksum_res = stream.get_data(32)
		if payload_checksum_res[0] != OK:
			return FWSaveTypes.Result.failure(FWSaveTypes.Error.CORRUPTED_FILE)
		file_data.header.payload_checksum = payload_checksum_res[1]
		
		file_data.toc[toc_entry.key] = toc_entry
	
	return FWSaveTypes.Result.success(file_data)

func encode(file_data: FWSaveTypes.FileData) -> FWSaveTypes.Result:
	match CURRENT_VERSION:
		1:
			return _encode_v1(file_data)
		_:
			return FWSaveTypes.Result.failure(FWSaveTypes.Error.UNKNOWN_HEADER_VERSION)

func _encode_v1(file_data: FWSaveTypes.FileData) -> FWSaveTypes.Result:
	var size: int = 256 + 80 * file_data.toc.size()
	for key in file_data.payloads:
		size += file_data.payloads[key].size()
	
	var buffer: PackedByteArray = PackedByteArray()
	buffer.resize(size)
	
	
	
	return FWSaveTypes.Result.failure(100)

func _encode_v1_header(file_data: FWSaveTypes.FileData, stream: StreamPeerBuffer):
	file_data.header.magic_number = MAGIC_NUMBER
	file_data.header.version = 1

func _encode_v1_toc():
	pass

func _encode_v1_payloads():
	pass
