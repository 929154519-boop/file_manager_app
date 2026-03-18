import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:archive/archive_io.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文件管理器',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FileManagerPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  List<FileSystemEntity> _files = [];
  String _currentPath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _loadRoot();
  }

  Future<void> _requestPermission() async {
    await Permission.storage.request();
  }

  Future<void> _loadRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    _currentPath = dir.path;
    _listFiles();
  }

  Future<void> _listFiles() async {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(_currentPath);
      final list = await dir.list().toList();
      list.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.path.compareTo(b.path);
      });
      _files = list;
    } catch (e) {}
    setState(() => _isLoading = false);
  }

  void _open(FileSystemEntity entity) {
    if (entity is Directory) {
      setState(() => _currentPath = entity.path);
      _listFiles();
    } else {
      OpenFile.open(entity.path);
    }
  }

  void _back() {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) {
      setState(() => _currentPath = parent);
      _listFiles();
    }
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("新建文件夹"),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                Directory("$_currentPath/$name").create();
                _listFiles();
              }
              Navigator.pop(c);
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(FileSystemEntity e) async {
    await e.delete(recursive: true);
    _listFiles();
  }

  Future<void> _pickAndCopy() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    for (final f in result.files) {
      if (f.path != null) {
        final source = File(f.path!);
        final name = f.name;
        await source.copy("$_currentPath/$name");
      }
    }
    _listFiles();
  }

  Future<void> _zip(List<FileSystemEntity> items) async {
    final name = "archive_${DateTime.now().millisecondsSinceEpoch}.zip";
    final out = "$_currentPath/$name";
    final zip = ZipFileEncoder();
    zip.create(out);
    for (final e in items) {
      if (e is File) {
        await zip.addFile(e);
      } else if (e is Directory) {
        await zip.addDirectory(e);
      }
    }
    zip.close();
    _listFiles();
  }

  Future<void> _unzip(File file) async {
    final toDir = Directory("${file.path.replaceAll(".zip", "")}");
    await toDir.create();
    await extractFileToDisk(file.path, toDir.path);
    _listFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("文件管理器"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        actions: [
          IconButton(icon: const Icon(Icons.create_new_folder), onPressed: _newFolder),
          IconButton(icon: const Icon(Icons.add_box), onPressed: _pickAndCopy),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (c, i) {
                final e = _files[i];
                final isDir = e is Directory;
                final name = e.path.split(Platform.pathSeparator).last;
                return ListTile(
                  leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file),
                  title: Text(name),
                  onTap: () => _open(e),
                  trailing: PopupMenuButton(
                    onSelected: (v) {
                      if (v == "del") _delete(e);
                      if (v == "zip" && !isDir && e.path.endsWith(".zip")) _unzip(e);
                    },
                    itemBuilder: (c) => [
                      const PopupMenuItem(value: "del", child: Text("删除")),
                      if (e.path.endsWith(".zip")) const PopupMenuItem(value: "zip", child: Text("解压")),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
