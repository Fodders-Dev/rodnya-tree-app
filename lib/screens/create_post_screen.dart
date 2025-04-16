import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/post_service.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/tree_provider.dart';
import 'package:go_router/go_router.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({Key? key}) : super(key: key);

  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  bool _isPublic = true;
  bool _isLoading = false;
  List<XFile> _selectedImages = [];
  
  final PostService _postService = PostService();
  final ImagePicker _picker = ImagePicker();
  String? _currentTreeId;

  @override
  void initState() {
    super.initState();
    _currentTreeId = Provider.of<TreeProvider>(context, listen: false).selectedTreeId;
  }
  
  Future<void> _pickImages() async {
    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        setState(() {
          _selectedImages = pickedFiles.take(5).toList();
        });
      }
    } catch (e) {
      print('Ошибка выбора изображений: $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выбрать изображения.')),
        );
      }
    }
  }
  
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }
  
  Future<void> _createPost() async {
    if (_contentController.text.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напишите что-нибудь или добавьте фото.')),
      );
      return;
    }

    if (_currentTreeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка: Не удалось определить дерево для публикации.')),
        );
        return;
    }

    setState(() { _isLoading = true; });

    try {
      // Создаем пост в Firestore
       await _postService.createPost(
         treeId: _currentTreeId!,
         content: _contentController.text,
         images: _selectedImages.isNotEmpty ? _selectedImages : null,
       );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пост успешно опубликован!')),
        );
        context.pop();
      }
    } catch (e) {
      print('Ошибка создания поста: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка публикации: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }
  
  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая публикация'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createPost,
            child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('ОПУБЛИКОВАТЬ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(
                hintText: 'Что у вас нового?',
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
              minLines: 3,
            ),
            
            const SizedBox(height: 16),

            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Добавить фото'),
              onPressed: _pickImages,
            ),
            const SizedBox(height: 16),

            if (_selectedImages.isNotEmpty)
              _buildImagePreviews(),

            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Публикация...', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreviews() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        return Stack(
          alignment: Alignment.topRight,
          children: [
            Image.file(
              File(_selectedImages[index].path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.black54),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.7),
              ),
              onPressed: () {
                setState(() {
                  _selectedImages.removeAt(index);
                });
              },
            ),
          ],
        );
      },
    );
  }
} 