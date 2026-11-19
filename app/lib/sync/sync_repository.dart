import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../data/local/task_local_datasource.dart';
import '../data/models/task.dart';
import '../data/remote/api_client.dart';

enum SyncPhase { idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSyncAt, this.message});
  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? message;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncAt, String? message}) =>
      SyncStatus(phase: phase ?? this.phase, lastSyncAt: lastSyncAt ?? this.lastSyncAt, message: message);
}

class PushReport {
  const PushReport({this.sent = 0, this.acked = 0, this.rejected = 0, this.failed = 0});
  final int sent;
  final int acked;
  final int rejected;
  final int failed;

  PushReport operator +(PushReport o) => PushReport(
      sent: sent + o.sent, acked: acked + o.acked, rejected: rejected + o.rejected, failed: failed + o.failed);

  @override
  String toString() => 'Push(sent=$sent, ack=$acked, rejected=$rejected, failed=$failed)';
}

class SyncReport {
  const SyncReport(this.push, this.pull);
  final PushReport push;
  final MergeStats pull;

  @override
  String toString() => 'SyncReport($push, $pull)';
}

/// Motor de reconciliación bidireccional:
///
///   01 PUSH  -> envía registros con is_synced = 0
///   02 ACK   -> marca is_synced = 1 lo que la nube confirmó
///   03 PULL  -> descarga cambios remotos desde el último cursor
///   04 MERGE -> resuelve colisiones por updated_at (LWW)
///
/// Todas las operaciones son idempotentes: si la app muere a mitad de un
/// ciclo, repetirlo no duplica datos (UUID del cliente + updated_at).
class SyncRepository {
  SyncRepository({required this.local, required this.remote});

  final TaskLocalDataSource local;
  final TaskRemoteApi remote;

  static const cursorKey = 'pull_cursor';

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());
  Future<SyncReport>? _inFlight;

  /// Ciclo completo. Si ya hay uno en curso, se reutiliza (evita carreras
  /// entre el listener de conectividad, el botón manual y el debounce).
  Future<SyncReport> sync() => _inFlight ??= _runCycle().whenComplete(() => _inFlight = null);

  Future<SyncReport> _runCycle() async {
    status.value = status.value.copyWith(phase: SyncPhase.syncing);
    try {
      final push = await pushPending();
      final pull = await pullAndMerge();
      await local.purgeSyncedTombstones();
      final report = SyncReport(push, pull);
      dev.log('$report', name: 'sync');
      status.value = SyncStatus(phase: SyncPhase.idle, lastSyncAt: DateTime.now());
      return report;
    } catch (e) {
      dev.log('Sync falló: $e', name: 'sync');
      status.value = status.value.copyWith(
        phase: SyncPhase.error,
        message: e is ApiException ? e.message : e.toString(),
      );
      rethrow;
    }
  }

  /// Fases 01 PUSH + 02 ACK.
  Future<PushReport> pushPending() async {
    final pending = await local.getPending();
    if (pending.isEmpty) return const PushReport();

    var report = const PushReport();
    for (var i = 0; i < pending.length; i += AppConfig.pushBatchSize) {
      final end = math.min(i + AppConfig.pushBatchSize, pending.length);
      final batch = pending.sublist(i, end);
      final sentById = {for (final t in batch) t.id: t};
      final results = await remote.pushTasks(batch);

      final toMerge = <Task>[];
      var acked = 0, rejected = 0, failed = 0;
      for (final r in results) {
        final sent = sentById[r.id];
        if (sent == null) continue;
        switch (r.status) {
          case 'applied':
          case 'duplicate':
            await local.markSynced(
              r.id,
              sentUpdatedAt: sent.updatedAt,
              version: r.task?.version ?? sent.version,
            );
            acked++;
          case 'rejected':
            // La nube tiene una versión más reciente: se integra vía MERGE (LWW).
            if (r.task != null) toMerge.add(r.task!);
            rejected++;
          default: // forbidden u otro: se deja pendiente y se reporta
            failed++;
        }
      }
      if (toMerge.isNotEmpty) await local.mergeRemote(toMerge);
      report += PushReport(sent: batch.length, acked: acked, rejected: rejected, failed: failed);
    }
    local.notifyChanged();
    return report;
  }

  /// Fases 03 PULL + 04 MERGE, paginado por cursor de revisión del servidor.
  Future<MergeStats> pullAndMerge() async {
    var cursor = int.tryParse(await local.getMeta(cursorKey) ?? '') ?? 0;
    var stats = const MergeStats();
    PullPage page;
    do {
      page = await remote.fetchChanges(since: cursor);
      stats += await local.mergeRemote(page.tasks);
      cursor = page.cursor;
      await local.setMeta(cursorKey, '$cursor');
    } while (page.hasMore && page.tasks.isNotEmpty);
    return stats;
  }

  void dispose() => status.dispose();
}
