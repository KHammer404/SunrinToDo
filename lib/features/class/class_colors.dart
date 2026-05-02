import 'package:flutter/material.dart';

const List<int> kClassColorValues = [
  0xFF4285F4,
  0xFF34A853,
  0xFFEA4335,
  0xFFFBBC04,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF607D8B,
];

const int kDefaultClassColorValue = 0xFF4285F4;

bool isSupportedClassColorValue(int value) => kClassColorValues.contains(value);

int classColorValueForId(String id) {
  if (id == 'personal') return kDefaultClassColorValue;
  return kClassColorValues[id.hashCode.abs() % kClassColorValues.length];
}

Color classColorFromId(String id) => Color(classColorValueForId(id));

Color classColorFromValue(Object? value, String fallbackId) {
  if (value is int && isSupportedClassColorValue(value)) {
    return Color(value);
  }
  return classColorFromId(fallbackId);
}
