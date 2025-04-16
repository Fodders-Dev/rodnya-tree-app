import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('О приложении'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 24),
            
            // Логотип приложения (можно заменить на Icon временно)
            Icon(
              Icons.family_restroom,
              size: 120,
              color: Theme.of(context).primaryColor,
            ),
            
            SizedBox(height: 24),
            
            // Название приложения
            Text(
              'Lineage',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            SizedBox(height: 8),
            
            // Версия
            Text(
              'Версия 1.0.0 (сборка 1)',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            
            SizedBox(height: 32),
            
            // Описание приложения
            Text(
              'Lineage - это приложение для создания и хранения семейного древа, которое поможет вам сохранить историю вашей семьи и поддерживать связь с близкими.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            
            SizedBox(height: 32),
            
            // Разработчики
            ListTile(
              title: Text('Разработчики'),
              subtitle: Text('Artem Kuznetsov'),
              leading: Icon(Icons.code),
            ),
            
            // Правовая информация (без функций запуска ссылок)
            ListTile(
              title: Text('Политика конфиденциальности'),
              leading: Icon(Icons.privacy_tip),
            ),
            
            ListTile(
              title: Text('Условия использования'),
              leading: Icon(Icons.description),
            ),
            
            SizedBox(height: 16),
            
            // Копирайт
            Text(
              '© 2023 Lineage. Все права защищены.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 