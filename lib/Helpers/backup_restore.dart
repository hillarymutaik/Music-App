import 'dart:io';

import 'package:blackhole/CustomWidgets/snackbar.dart';
import 'package:blackhole/Helpers/picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

Future<String> createBackup(
  BuildContext context,
  List items,
  Map<String, List> boxNameData, {
  String? path,
  String? fileName,
  bool showDialog = true,
}) async {
  if (Platform.isAndroid) {
    PermissionStatus status = await Permission.storage.status;
    if (status.isDenied) {
      await [
        Permission.storage,
        Permission.accessMediaLocation,
        Permission.mediaLibrary,
      ].request();
    }
    status = await Permission.storage.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }
  final String savePath = path ??
      await Picker.selectFolder(
        context: context,
        message: AppLocalizations.of(context)!.selectBackLocation,
      );
  if (savePath.trim() != '') {
    try {
      final saveDir = Directory(savePath);
      final dirExists = await saveDir.exists();
      if (!dirExists) saveDir.create(recursive: true);
      final List<File> files = [];
      final List boxNames = [];

      for (int i = 0; i < items.length; i++) {
        boxNames.addAll(boxNameData[items[i]]!);
      }

      for (int i = 0; i < boxNames.length; i++) {
        await Hive.openBox(boxNames[i].toString());
        try {
          await File(Hive.box(boxNames[i].toString()).path!)
              .copy('$savePath/${boxNames[i]}.hive');
        } catch (e) {
          await [
            Permission.manageExternalStorage,
          ].request();
          await File(Hive.box(boxNames[i].toString()).path!)
              .copy('$savePath/${boxNames[i]}.hive');
        }

        files.add(File('$savePath/${boxNames[i]}.hive'));
      }

      final now = DateTime.now();
      final String time =
          '${now.hour}${now.minute}_${now.day}${now.month}${now.year}';
      final zipFile =
          File('$savePath/${fileName ?? "BlackHole_Backup_$time"}.zip');

      if ((Platform.isIOS || Platform.isMacOS) && await zipFile.exists()) {
        await zipFile.delete();
      }

      await ZipFile.createFromFiles(
        sourceDir: saveDir,
        files: files,
        zipFile: zipFile,
      );
      for (int i = 0; i < files.length; i++) {
        files[i].delete();
      }
      if (showDialog) {
        ShowSnackBar().showSnackBar(
          context,
          AppLocalizations.of(context)!.backupSuccess,
        );
      }
      return '';
    } catch (e) {
      Logger.root.severe('Error in creating backup', e);
      ShowSnackBar().showSnackBar(
        context,
        '${AppLocalizations.of(context)!.failedCreateBackup}\nError: $e',
      );
      return e.toString();
    }
  } else {
    ShowSnackBar().showSnackBar(
      context,
      AppLocalizations.of(context)!.noFolderSelected,
    );
    return 'No Folder Selected';
  }
}

Future<void> restore(
  BuildContext context,
) async {
  Logger.root.info('Prompting for restore file selection');
  final String savePath = await Picker.selectFile(
    context: context,
    // ext: ['zip'],
    message: AppLocalizations.of(context)!.selectBackFile,
  );
  Logger.root.info('Selected restore file path: $savePath');
  if (savePath != '') {
    final isZip = savePath.endsWith('.zip');
    if (isZip || savePath.endsWith('.hive')) {
      final File zipFile = File(savePath);
      final Directory tempDir = await getTemporaryDirectory();
      Directory destinationDir = Directory('${tempDir.path}/restore');

      try {
        if (isZip) {
          Logger.root.info('Extracting backup file');
          await ZipFile.extractToDirectory(
            zipFile: zipFile,
            destinationDir: destinationDir,
          );
        } else {
          Logger.root.info('Hive file is selected');
          final splitPath = savePath.split('/');
          splitPath.removeLast();
          Logger.root.info('Changing path to ${splitPath.join("/")}');
          destinationDir = Directory(splitPath.join('/'));
        }
        final List<FileSystemEntity> files = await destinationDir
            .list()
            .where((element) => element.path.endsWith('.hive'))
            .toList();
        Logger.root.info('Found ${files.length} backup files');

        for (int i = 0; i < files.length; i++) {
          final String backupPath = files[i].path;
          final String boxName =
              backupPath.split('/').last.replaceAll('.hive', '');
          final Box box = await Hive.openBox(boxName);
          final String boxPath = box.path!;
          await box.close();

          try {
            await File(backupPath).copy(boxPath);
          } finally {
            await Hive.openBox(boxName);
          }
        }
        if (isZip) {
          await destinationDir.delete(recursive: true);
        }
        ShowSnackBar()
            .showSnackBar(context, AppLocalizations.of(context)!.importSuccess);
      } catch (e) {
        Logger.root.severe('Error in restoring backup', e);
        ShowSnackBar().showSnackBar(
          context,
          '${AppLocalizations.of(context)!.failedImport}\nError: $e',
        );
      }
    } else {
      Logger.root.severe('Error in restoring backup', 'Not a zip file');
      ShowSnackBar().showSnackBar(
        context,
        '${AppLocalizations.of(context)!.failedImport}\nSelected file is not a zip file.',
      );
      return;
    }
  } else {
    Logger.root.severe('Error in restoring backup', 'No file selected');
    ShowSnackBar().showSnackBar(
      context,
      AppLocalizations.of(context)!.noFileSelected,
    );
  }
}
