// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dataset_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DatasetItemAdapter extends TypeAdapter<DatasetItem> {
  @override
  final int typeId = 0;

  @override
  DatasetItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DatasetItem(
      id: fields[0] as String,
      name: fields[1] as String,
      imagePath: fields[2] as String,
      embedding: (fields[3] as List).cast<double>(),
      colorValue: fields[4] as int,
      createdAt: fields[5] as DateTime,
      source: fields[6] as String,
      ocrText: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DatasetItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.imagePath)
      ..writeByte(3)
      ..write(obj.embedding)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.source)
      ..writeByte(7)
      ..write(obj.ocrText);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatasetItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
