import 'package:flutter/material.dart';

class RelativeProfileScreen extends StatefulWidget {
  // ... (existing code)
  @override
  _RelativeProfileScreenState createState() => _RelativeProfileScreenState();
}

class _RelativeProfileScreenState extends State<RelativeProfileScreen> {
  // ... (existing code)

  @override
  Widget build(BuildContext context) {
    // ... (existing code)

    return Scaffold(
      appBar: AppBar(
        title: Text('Профиль родственника'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ... (existing code)
            _buildRelationshipsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationshipsSection() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Родственные связи',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            
            _relationToUser != null
                ? _buildRelationshipCard(
                    title: 'Вам приходится',
                    relationDescription: _getRelationDescription(_relationToUser!),
                    icon: Icons.person,
                  )
                : Text('Связь с вами не установлена'),
            
            SizedBox(height: 12),
            
            if (_relationships.isNotEmpty)
              ...(_relationships.map((relation) => 
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: _buildRelationshipCard(
                    title: relation.relatedPersonName,
                    relationDescription: relation.relationDescription,
                    icon: Icons.family_restroom,
                    onTap: () => _navigateToRelatedPerson(relation.relatedPersonId),
                  ),
                )
              ).toList())
            else
              Text('Нет других связей'),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationshipCard({
    required String title,
    required String relationDescription,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(relationDescription),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ... (rest of the existing code)
} 