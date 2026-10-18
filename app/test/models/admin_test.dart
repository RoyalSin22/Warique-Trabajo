import 'package:flutter_test/flutter_test.dart';
import 'package:warique_app/models/admin.dart';

void main() {
  Map<String, dynamic> status({String? copyTarget, bool? uploaderRunning}) => {
    'configured': true,
    'ok': true,
    'needsAttention': false,
    'copied': true,
    'time': '2026-10-03T00:30:00.000Z',
    'ageHours': 2.0,
    'file': 'x.zip',
    'error': null,
    'copyTarget': copyTarget,
    'uploaderRunning': uploaderRunning,
  };

  test('a copy in the Google Drive folder is only "in the cloud" while Drive runs', () {
    expect(BackupStatus.fromJson(status(copyTarget: 'drive', uploaderRunning: false)).notUploading, isTrue);
    expect(BackupStatus.fromJson(status(copyTarget: 'drive', uploaderRunning: true)).notUploading, isFalse);
    expect(BackupStatus.fromJson(status(copyTarget: 'folder')).notUploading, isFalse);
    expect(BackupStatus.fromJson(status()).notUploading, isFalse); // written by an older backup.ps1
  });
}
