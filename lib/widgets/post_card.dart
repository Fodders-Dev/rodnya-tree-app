import 'package:flutter/material.dart' hide CarouselController; // <<< Скрываем CarouselController из material
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:cached_network_image/cached_network_image.dart'; // Для кэширования изображений
import 'package:carousel_slider/carousel_slider.dart'; // Для слайдера изображений
import '../models/post.dart';
import '../services/post_service.dart'; // Для вызова toggleLike
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';

class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({required this.post, Key? key}) : super(key: key);

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final PostService _postService = PostService();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Локальное состояние для оптимистичного обновления лайков
  late bool _isLikedByCurrentUser;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _isLikedByCurrentUser = _currentUserId != null && widget.post.likedBy.contains(_currentUserId!);
    _likeCount = widget.post.likeCount;
  }

  // Метод для переключения лайка с оптимистичным обновлением
  Future<void> _toggleLike() async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы поставить лайк')),
      );
      return;
    }

    // Оптимистичное обновление UI
    setState(() {
      if (_isLikedByCurrentUser) {
        _likeCount--;
      } else {
        _likeCount++;
      }
      _isLikedByCurrentUser = !_isLikedByCurrentUser;
    });

    try {
      await _postService.toggleLike(widget.post.id);
    } catch (e) {
      print('Ошибка при переключении лайка: $e');
      // Откатываем изменения в UI в случае ошибки
      setState(() {
        if (_isLikedByCurrentUser) { // Теперь это новое состояние, откатываем обратно
          _likeCount--;
        } else {
          _likeCount++;
        }
        _isLikedByCurrentUser = !_isLikedByCurrentUser;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: Не удалось ${!_isLikedByCurrentUser ? "поставить" : "убрать"} лайк')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка поста (автор, дата)
          _buildPostHeader(),
          
          // Текст поста
          if (widget.post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Text(widget.post.content),
            ),
            
          // Изображения поста (карусель)
          if (widget.post.imageUrls != null && widget.post.imageUrls!.isNotEmpty)
            _buildPostImages(),
            
          // Разделитель
          Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16),
          
          // Кнопки действий (лайк, коммент)
          _buildPostActions(),
        ],
      ),
    );
  }

  Widget _buildPostHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: widget.post.authorPhotoUrl != null && widget.post.authorPhotoUrl!.isNotEmpty
                ? CachedNetworkImageProvider(widget.post.authorPhotoUrl!) // Используем CachedNetworkImageProvider
                : null,
            child: widget.post.authorPhotoUrl == null || widget.post.authorPhotoUrl!.isEmpty
                ? const Icon(Icons.person, size: 20, color: Colors.grey)
                : null,
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.authorName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('d MMMM yyyy в HH:mm', 'ru').format(widget.post.createdAt),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          // TODO: Добавить меню поста (редактировать/удалить), если нужно
          // IconButton(onPressed: () {}, icon: Icon(Icons.more_vert)),
        ],
      ),
    );
  }

  Widget _buildPostImages() {
    final images = widget.post.imageUrls!;
    if (images.length == 1) {
      // Одно изображение
      return Padding(
        padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: CachedNetworkImage(
            imageUrl: images.first,
            fit: BoxFit.contain,
            placeholder: (context, url) => Container(color: Colors.grey.shade300, child: const Center(child: CircularProgressIndicator())), // Плейсхолдер
            errorWidget: (context, url, error) {
              print('[PostCard] Error loading image: $url, Error: $error');
              return Container(color: Colors.grey.shade300, child: const Center(child: Icon(Icons.error))); // Показываем иконку ошибки
            },
          ),
        ),
      );
    } else {
      // Карусель для нескольких изображений
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: CarouselSlider.builder(
          itemCount: images.length,
          itemBuilder: (context, index, realIdx) {
            final imageUrl = images[index];
            print('[PostCard] Loading image for carousel: $imageUrl');
            return CachedNetworkImage(
              imageUrl: imageUrl,
              imageBuilder: (context, imageProvider) {
                print('[PostCard] Carousel image loaded successfully: $imageUrl');
                return Image(image: imageProvider, fit: BoxFit.cover);
              },
              fit: BoxFit.contain,
              placeholder: (context, url) => Container(color: Colors.grey.shade300, child: const Center(child: CircularProgressIndicator())), // Плейсхолдер
              errorWidget: (context, url, error) {
                print('[PostCard] Error loading carousel image: $url, Error: $error');
                return Container(color: Colors.grey.shade300, child: const Center(child: Icon(Icons.error))); // Показываем иконку ошибки
              },
              width: MediaQuery.of(context).size.width, // Ширина экрана
            );
          },
          options: CarouselOptions(
            aspectRatio: 16 / 9,
            viewportFraction: 1.0, // Одно изображение на весь экран слайдера
            enableInfiniteScroll: false, // Отключаем бесконечную прокрутку
            autoPlay: false, // Отключаем автопрокрутку
             enlargeCenterPage: false,
          ),
        ),
      );
    }
  }

  Widget _buildPostActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Кнопка лайка
          TextButton.icon(
            icon: Icon(
              _isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
              color: _isLikedByCurrentUser ? Colors.redAccent : Colors.grey.shade600,
              size: 20,
            ),
            label: Text(
              _likeCount.toString(),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            onPressed: _toggleLike,
            style: TextButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), // Уменьшаем отступы
               minimumSize: Size(0, 30), // Уменьшаем минимальный размер
            ),
          ),
          const SizedBox(width: 16),
          // Кнопка комментирования
          TextButton.icon(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: Colors.grey.shade600,
              size: 20,
            ),
            label: Text(
              widget.post.commentCount.toString(),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            onPressed: () {
              // TODO: Реализовать переход к комментариям
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Комментарии еще не реализованы')),
              );
            },
             style: TextButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
               minimumSize: Size(0, 30),
            ),
          ),
          // TODO: Кнопка Поделиться?
        ],
      ),
    );
  }
} 