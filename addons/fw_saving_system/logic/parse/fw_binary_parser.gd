
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
	self.game_literal = _crop_string(game_literal)
	self.game_version = _crop_string(game_version)
	self.godot_version = _crop_string(godot_version)

func _crop_string(original: String, size: int = 31):
	var bytes: PackedByteArray = original.to_utf8_buffer()
	if bytes.size() <= size:
		return original
	return bytes.slice(0, size).get_string_from_utf8()

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
	
	file_data.header.game_literal = stream.get_utf8_string(32)
	if game_literal != self.game_literal:
		return FWSaveTypes.Result.failure(FWSaveTypes.Error.DIFFERENT_GAME_LITERAL)
	stream.seek(48)
	
	file_data.header.game_version = stream.get_utf8_string(32)
	stream.seek(80)
	
	# Godot Version is currently skipped
	file_data.header.godot_version = stream.get_utf8_string(32)
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
		
		toc_entry.key = stream.get_utf8_string(32)
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
	
	var stream: StreamPeerBuffer = StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = buffer

	file_data.header.file_size = size

	var res: FWSaveTypes.Result = _encode_v1_payloads(file_data, stream)
	if not res.is_ok():
		return res
	res = _encode_v1_toc(file_data, stream)
	if not res.is_ok():
		return res
	res = _encode_v1_header(file_data, stream)
	if not res.is_ok():
		return res

	return FWSaveTypes.Result.success(stream.data_array)

func _encode_v1_payloads(file_data: FWSaveTypes.FileData, stream: StreamPeerBuffer) -> FWSaveTypes.Result:
	stream.seek(256 + 80 * file_data.toc.size())

	for key in file_data.payloads:
		if not key in file_data.toc:
			FWSaveTypes.Result.failure(FWSaveTypes.Error.TOC_ENTRIES_NOT_PRESENT)
		file_data.toc[key].payload_offset = stream.get_position()
		
		var err = stream.put_data(file_data.payloads[key])
		if err != OK:
			FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_PAYLOAD_STREAMING_ERROR)
	
	return FWSaveTypes.Result.success(file_data)

func _encode_v1_toc(file_data: FWSaveTypes.FileData, stream: StreamPeerBuffer):
	var ctx = HashingContext.new()
	stream.seek(256)

	for key in file_data.toc:
		if key.to_utf8_buffer().size() > 31:
			FWSaveTypes.Result.failure(FWSaveTypes.Error.INVALID_KEY_LENGTH)

		var pos: int = stream.get_position()
		var entry: FWSaveTypes.TocEntry = file_data.toc[key]

		if key in file_data.payloads:
			var payload: PackedByteArray = file_data.payloads[key]
			entry.payload_disk_size = payload.size()
			
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(payload)
			var checksum: PackedByteArray = ctx.finish()
			entry.payload_checksum = checksum

		var err: int = stream.put_data(key.to_utf8_buffer())
		if err != OK:
			FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_TOC_KEY_STREAMING_ERROR)
		stream.seek(pos + 32)
		stream.put_u32(entry.payload_offset)
		stream.put_u32(entry.payload_disk_size)
		stream.put_u32(entry.payload_uncompressed_size)
		stream.put_u16(entry.encoding)
		stream.put_u16(entry.flags)
		err = stream.put_data(entry.payload_checksum)
		if err != OK:
			FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_PAYLOAD_CHECKSUM_STREAMING_ERROR)
	
	return FWSaveTypes.Result.success(file_data)

func _encode_v1_header(file_data: FWSaveTypes.FileData, stream: StreamPeerBuffer):
	var ctx = HashingContext.new()
	stream.seek(0)

	file_data.header.magic_number = MAGIC_NUMBER
	file_data.header.version = 1
	file_data.header.toc_count = file_data.toc.size()

	file_data.header.game_literal = game_literal
	file_data.header.game_version = game_version
	file_data.header.godot_version = godot_version

	stream.put_u32(file_data.header.magic_number)
	stream.put_u32(file_data.header.version)
	stream.put_u32(file_data.header.file_size)
	stream.put_u16(file_data.header.toc_count)
	stream.put_u16(file_data.header.flags)

	var err: int = stream.put_data(file_data.header.game_literal.to_utf8_buffer())
	if err != OK:
		FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_GAME_LITERAL_STREAMING_ERROR)
	stream.seek(48)
	err = stream.put_data(file_data.header.game_version.to_utf8_buffer())
	if err != OK:
		FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_GAME_VERSION_STREAMING_ERROR)
	stream.seek(80)
	err = stream.put_data(file_data.header.godot_version.to_utf8_buffer())
	if err != OK:
		FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_GODOT_VERSION_STREAMING_ERROR)
	stream.seek(112)

	stream.seek(192)

	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(stream.data_array.slice(256, 256 + 80 * file_data.header.toc_count))
	file_data.header.toc_checksum = ctx.finish()
	err = stream.put_data(file_data.header.toc_checksum)
	if err != OK:
		FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_TOC_CHECKSUM_STREAMING_ERROR)

	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(stream.data_array.slice(0, 224))
	file_data.header.header_checksum = ctx.finish()
	err = stream.put_data(file_data.header.header_checksum)
	if err != OK:
		FWSaveTypes.Result.failure(FWSaveTypes.Error.ENCODED_HEADER_CHECKSUM_STREAMING_ERROR)

	return FWSaveTypes.Result.success(file_data)
