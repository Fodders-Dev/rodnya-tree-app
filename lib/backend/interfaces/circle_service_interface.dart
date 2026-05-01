import '../../models/circle.dart';

abstract class CircleServiceInterface {
  Future<List<FamilyCircle>> getCircles(String treeId);
}
