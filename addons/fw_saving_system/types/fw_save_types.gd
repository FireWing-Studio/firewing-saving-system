
class_name FWSaveTypes
extends RefCounted

enum Error {
	OK = 2000,
	
	IO_ERROR = 3000,
	CORRUPTED_FILE = 3001,
	
	DATA_ERROR = 4000,
	FILE_SIZE_TOO_SMALL = 4001,
	INVALID_FILE_TYPE = 4002,
	UNKNOWN_HEADER_VERSION = 4003,
	DIFFERENT_GAME_LITERAL = 4004,
	TOC_ENTRIES_NOT_PRESENT = 4005,
	HEADER_NOT_PRESENT = 4006,
	INVALID_KEY_LENGTH = 4007,
	
	CHECKSUM_ERROR = 5000,
	INVALID_TOC_CHECKSUM = 5001,
	INVALID_HEADER_CHECKSUM = 5002,
	INVALID_PAYLOAD_CHECKSUM = 5003,

	ENCODING_ERROR = 6000,
	ENCODED_PAYLOAD_STREAMING_ERROR = 6001,
	ENCODED_TOC_KEY_STREAMING_ERROR = 6002,
	ENCODED_TOC_CHECKSUM_STREAMING_ERROR = 6003,
	ENCODED_PAYLOAD_CHECKSUM_STREAMING_ERROR = 6004,
	ENCODED_HEADER_CHECKSUM_STREAMING_ERROR = 6005,
	ENCODED_GAME_LITERAL_STREAMING_ERROR = 6006,
	ENCODED_GAME_VERSION_STREAMING_ERROR = 6007,
	ENCODED_GODOT_VERSION_STREAMING_ERROR = 6008,
}

enum Encoding {
	INVALID = 0,

	BINARY = 1,
	BINARY_ZSTD = 2
}

enum HeaderFlags {
	NONE = 0
}

enum TocEntryFlags {
	NONE = 0,
	
	PRIORITY = 1 << 0
}

class Result extends RefCounted:
	var value: Variant
	var error: Error
	
	func _init(val, err):
		value = val
		error = err
	
	func is_ok() -> bool:
		return error == null || error == Error.OK

	static func success(val: Variant) -> Result:
		return Result.new(val, FWSaveTypes.Error.OK)

	static func failure(err: FWSaveTypes.Error) -> Result:
		return Result.new(null, err)

class Header extends RefCounted:
	var magic_number: int
	var version: int
	var file_size: int
	var toc_count: int
	var flags: HeaderFlags

	var game_literal: StringName
	var game_version: StringName
	var godot_version: StringName

	var toc_checksum: PackedByteArray
	var header_checksum: PackedByteArray

class TocEntry extends RefCounted:
	var payload_offset: int
	var payload_disk_size: int
	var payload_uncompressed_size: int
	var encoding: Encoding
	var flags: TocEntryFlags
	
	var payload_checksum: PackedByteArray

class FileData extends RefCounted:
	var header: Header = Header.new()
	var toc: Dictionary[StringName, TocEntry] = {}
	var payloads: Dictionary[StringName, PackedByteArray] = {}
