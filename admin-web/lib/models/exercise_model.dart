import '../services/api_client.dart';

class MuscleGroup {
  final int groupId;
  final String groupName;
  final int? zone;
  final String? imageUrl;

  MuscleGroup({
    required this.groupId,
    required this.groupName,
    this.zone,
    this.imageUrl,
  });

  factory MuscleGroup.fromJson(Map<String, dynamic> json) => MuscleGroup(
        groupId: json['mug_id'] ?? json['group_id'] ?? json['id'] ?? 0,
        groupName: json['mug_name'] ?? json['group_name'] ?? '',
        zone: json['mug_zone'] as int? ?? json['zone'] as int?,
        imageUrl: json['mug_image']?.toString() ?? json['image_url']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'mug_name': groupName,
        'mug_zone': zone,
        'mug_image': imageUrl,
      };
}

// 1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight
enum EquipmentType {
  barbell(1, 'Barbell'),
  dumbbell(2, 'Dumbbell'),
  machine(3, 'Machine'),
  cable(4, 'Cable'),
  bodyweight(5, 'Bodyweight');

  final int value;
  final String label;
  const EquipmentType(this.value, this.label);

  static EquipmentType fromValue(int v) =>
      EquipmentType.values.firstWhere((e) => e.value == v,
          orElse: () => EquipmentType.bodyweight);
}

class Exercise {
  final int exerciseId;
  final String exerciseName;
  final String description;
  final String technique;
  final String difficulty;
  final String? imageUrl;
  final String? videoUrl;
  final String? loopVideoUrl;
  final EquipmentType equipment;
  final int? muscleGroupId;
  final int exerciseType;    // 1=หลายกลุ่ม, 2=เฉพาะส่วน
  final String muscleGroupName; // ชื่อกลุ่มกล้ามเนื้อหลัก เช่น ขา, อก

  Exercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.description,
    this.technique = '',
    required this.difficulty,
    this.imageUrl,
    this.videoUrl,
    this.loopVideoUrl,
    this.equipment = EquipmentType.bodyweight,
    this.muscleGroupId,
    this.exerciseType = 1,
    this.muscleGroupName = '',
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final muscleGroupJson = json['muscle_group'] as Map<String, dynamic>?;
    return Exercise(
      exerciseId: json['wet_id'] ?? json['exercise_id'] ?? json['id'] ?? 0,
      exerciseName: json['wet_name'] ?? json['exercise_name'] ?? '',
      description: json['wet_description'] ?? json['description'] ?? '',
      technique: json['wet_technique'] ?? json['technique'] ?? '',
      difficulty: (json['wet_difficulty'] ?? json['difficulty'] ?? 'beginner').toString(),
      imageUrl: ApiClient.prefixPath(json['wet_image'] ?? json['image_url']),
      videoUrl: ApiClient.prefixPath(json['wet_video'] ?? json['video_url']),
      loopVideoUrl: ApiClient.prefixPath(json['wet_loop_video']),
      equipment: EquipmentType.fromValue(
          (json['wet_equipment'] ?? json['equipment'] ?? 5) as int),
      muscleGroupId: json['mug_id'] as int?,
      exerciseType: (json['wet_exercise_type'] ?? 1) as int,
      muscleGroupName: muscleGroupJson?['mug_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'wet_name': exerciseName,
        'wet_description': description,
        'wet_difficulty': difficulty,
        'wet_image': imageUrl,
        'wet_equipment': equipment.value,
        'mug_id': muscleGroupId,
      };
}

class ExerciseMuscle {
  final int id;
  final int exerciseId;
  final int muscleGroupId;
  final String exerciseName;
  final String muscleName;
  final bool isPrimary;

  ExerciseMuscle({
    required this.id,
    required this.exerciseId,
    required this.muscleGroupId,
    required this.exerciseName,
    required this.muscleName,
    required this.isPrimary,
  });

  factory ExerciseMuscle.fromJson(Map<String, dynamic> json) => ExerciseMuscle(
        id: json['emd_id'] ?? json['id'] ?? json['exm_id'] ?? 0,
        exerciseId: json['wet_id'] ?? json['exercise_id'] ?? 0,
        muscleGroupId: json['mug_id'] ?? json['muscle_group_id'] ?? 0,
        exerciseName: json['exercise'] ?? json['wet_name'] ?? '',
        muscleName: json['muscle'] ?? json['mug_name'] ?? '',
        isPrimary: json['emd_priority'] == 1 || json['type'] == 'หลัก' || json['is_primary'] == true,
      );
}

class CardioCategory {
  final int categoryId;
  final String categoryName;

  CardioCategory({required this.categoryId, required this.categoryName});

  factory CardioCategory.fromJson(Map<String, dynamic> json) => CardioCategory(
        categoryId: json['cdc_id'] ?? 0,
        categoryName: json['cdc_name'] ?? '',
      );

  Map<String, dynamic> toJson() => {'cdc_name': categoryName};
}

class CardioType {
  final int typeId;
  final String typeName;
  final double mets;
  final String description;
  final String technique;
  final String? imageUrl;
  final String? videoUrl;
  final String? loopVideoUrl;
  final bool hasDistance;
  final int categoryId;

  CardioType({
    required this.typeId,
    required this.typeName,
    required this.mets,
    required this.description,
    this.technique = '',
    this.imageUrl,
    this.videoUrl,
    this.loopVideoUrl,
    this.hasDistance = false,
    this.categoryId = 0,
  });

  factory CardioType.fromJson(Map<String, dynamic> json) => CardioType(
        typeId: json['cdo_id'] ?? json['type_id'] ?? json['id'] ?? 0,
        typeName: json['cdo_name'] ?? json['type_name'] ?? '',
        mets: (json['cdo_mets'] ?? json['mets'] ?? 0).toDouble(),
        description: json['cdo_description'] ?? json['description'] ?? '',
        technique: json['cdo_technique'] ?? json['technique'] ?? '',
        imageUrl: ApiClient.prefixPath(json['cdo_image'] ?? json['image_url']),
        videoUrl: ApiClient.prefixPath(json['cdo_video'] ?? json['video_url']),
        loopVideoUrl: ApiClient.prefixPath(json['cdo_loop_video'] ?? json['loop_video_url']),
        hasDistance: (json['cdo_has_distance'] ?? 0) == 1,
        categoryId: (json['cdc_id'] ?? json['category_id'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'cdo_name': typeName,
        'cdo_mets': mets,
        'cdo_description': description,
      };
}
