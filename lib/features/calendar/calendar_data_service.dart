import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sunrintodo/features/calendar/calendar_models.dart';
import 'package:sunrintodo/features/class/class_colors.dart';

class CalendarDataService {
  CalendarDataService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<CalendarSpace>> watchSpaces({
    required String uid,
    required String userName,
    required Set<String> pinnedSpaceIds,
  }) {
    return _firestore
        .collection('classes')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          final classSpaces =
              snapshot.docs.map((doc) {
                  final data = doc.data();
                  final rawMemberNames =
                      data['memberNames'] as Map<String, dynamic>?;
                  return CalendarSpace(
                    id: doc.id,
                    name: data['name'] as String,
                    color: classColorFromValue(data['colorValue'], doc.id),
                    memberNames:
                        rawMemberNames?.map(
                          (key, value) => MapEntry(key, value.toString()),
                        ) ??
                        const {},
                  );
                }).toList()
                ..sort((a, b) => compareCalendarSpaces(a, b, pinnedSpaceIds));

          return [
            CalendarSpace(
              id: 'personal',
              name: '개인',
              color: const Color(0xFF4285F4),
              memberNames: {uid: userName},
            ),
            ...classSpaces,
          ];
        });
  }

  Stream<List<CalendarEvent>> watchUserEvents({required String uid}) {
    return Stream.multi((controller) {
      List<CalendarEvent> personalEvents = const [];
      final classEventsByChunk = <int, List<CalendarEvent>>{};
      final classSubscriptions =
          <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      personalSubscription;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      classesSubscription;
      var closed = false;
      Future<void> rebindQueue = Future.value();

      void emitMerged() {
        if (closed) return;

        final merged = <String, CalendarEvent>{};
        for (final event in personalEvents) {
          merged[event.id] = event;
        }
        for (final events in classEventsByChunk.values) {
          for (final event in events) {
            merged[event.id] = event;
          }
        }

        final sorted = merged.values.toList()..sort(compareCalendarEvents);
        controller.add(sorted);
      }

      Future<void> rebindClassSubscriptions(List<String> classIds) async {
        for (final subscription in classSubscriptions) {
          await subscription.cancel();
        }
        classSubscriptions.clear();
        classEventsByChunk.clear();

        if (closed) return;

        final chunks = chunkCalendarClassIds(classIds);
        if (chunks.isEmpty) {
          emitMerged();
          return;
        }

        for (var index = 0; index < chunks.length; index++) {
          final subscription = _firestore
              .collection('events')
              .where('classId', whereIn: chunks[index])
              .snapshots()
              .listen((snapshot) {
                if (closed) return;
                classEventsByChunk[index] = snapshot.docs
                    .map(CalendarEvent.fromFirestore)
                    .toList();
                emitMerged();
              }, onError: controller.addError);
          classSubscriptions.add(subscription);
        }
      }

      personalSubscription = _firestore
          .collection('events')
          .where('classId', isEqualTo: 'personal')
          .where('createdBy', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) {
            if (closed) return;
            personalEvents = snapshot.docs
                .map(CalendarEvent.fromFirestore)
                .toList();
            emitMerged();
          }, onError: controller.addError);

      classesSubscription = _firestore
          .collection('classes')
          .where('memberIds', arrayContains: uid)
          .snapshots()
          .listen((snapshot) {
            final classIds = snapshot.docs.map((doc) => doc.id).toList();
            rebindQueue = rebindQueue.then(
              (_) => rebindClassSubscriptions(classIds),
            );
            unawaited(rebindQueue);
          }, onError: controller.addError);

      controller.onCancel = () async {
        closed = true;
        await classesSubscription?.cancel();
        await personalSubscription?.cancel();
        for (final subscription in classSubscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  Stream<List<CalendarEvent>> watchSpaceEvents({
    required String uid,
    required String spaceId,
  }) {
    final Query<Map<String, dynamic>> query = spaceId == 'personal'
        ? _firestore
              .collection('events')
              .where('classId', isEqualTo: 'personal')
              .where('createdBy', isEqualTo: uid)
        : _firestore.collection('events').where('classId', isEqualTo: spaceId);

    return query.snapshots().map((snapshot) {
      final events = snapshot.docs.map(CalendarEvent.fromFirestore).toList()
        ..sort(compareCalendarEvents);
      return events;
    });
  }
}

List<List<String>> chunkCalendarClassIds(List<String> classIds) {
  final uniqueIds = classIds.toSet().toList();
  if (uniqueIds.isEmpty) {
    return const <List<String>>[];
  }

  final chunks = <List<String>>[];
  for (var index = 0; index < uniqueIds.length; index += 10) {
    final end = (index + 10 < uniqueIds.length) ? index + 10 : uniqueIds.length;
    chunks.add(uniqueIds.sublist(index, end));
  }
  return chunks;
}
