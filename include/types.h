#ifndef HARE_TYPES_H
#define HARE_TYPES_H

enum type_storage {
	// Scalar types
	TYPE_STORAGE_U8,
	TYPE_STORAGE_U16,
	TYPE_STORAGE_U32,
	TYPE_STORAGE_U64,
	TYPE_STORAGE_I8,
	TYPE_STORAGE_I16,
	TYPE_STORAGE_I32,
	TYPE_STORAGE_I64,
	TYPE_STORAGE_INT,
	TYPE_STORAGE_RUNE,
	TYPE_STORAGE_UINT,
	TYPE_STORAGE_UINTPTR,
	TYPE_STORAGE_SIZE,
	TYPE_STORAGE_F32,
	TYPE_STORAGE_F64,
	// Aggregate types
	TYPE_STORAGE_STRING,
};

const char *type_storage_unparse(enum type_storage storage);
#endif
