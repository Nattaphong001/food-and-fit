import '../services/api_client.dart';

class NutritionCategory {
  final int categoryId;
  final String categoryName;

  NutritionCategory({required this.categoryId, required this.categoryName});

  factory NutritionCategory.fromJson(Map<String, dynamic> json) => NutritionCategory(
        categoryId: json['nttc_id'] ?? json['category_id'] ?? json['id'] ?? 0,
        categoryName: json['nttc_name'] ?? json['category_name'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'nttc_name': categoryName,
      };
}

class Food {
  final int foodId;
  final int categoryId;
  final String foodName;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final String unit;
  final String? imageUrl;

  Food({
    required this.foodId,
    required this.categoryId,
    required this.foodName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.fiber = 0.0,
    required this.unit,
    this.imageUrl,
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
        foodId: json['ntt_id'] ?? json['food_id'] ?? json['id'] ?? 0,
        categoryId: json['nttc_id'] ?? json['category_id'] ?? 0,
        foodName: json['ntt_food_name'] ?? json['food_name'] ?? '',
        calories: (json['ntt_calories'] ?? json['calories'] ?? 0).toDouble(),
        protein: (json['ntt_protein'] ?? json['protein'] ?? 0).toDouble(),
        carbs: (json['ntt_carbs'] ?? json['carbs'] ?? 0).toDouble(),
        fat: (json['ntt_fat'] ?? json['fat'] ?? 0).toDouble(),
        fiber: (json['ntt_fiber'] ?? json['fiber'] ?? 0).toDouble(),
        unit: json['ntt_unit'] ?? json['unit'] ?? 'กรัม',
        imageUrl: ApiClient.prefixPath(json['ntt_food_image'] ?? json['image_url']),
      );

  Map<String, dynamic> toJson() => {
        'ntt_food_name': foodName,
        'ntt_calories': calories,
        'ntt_protein': protein,
        'ntt_carbs': carbs,
        'ntt_fat': fat,
        'ntt_unit': unit,
        'nttc_id': categoryId,
        'ntt_food_image': imageUrl,
      };
}

class DailyNutrition {
  final int id;
  final int foodId;
  final String foodName;
  final double quantity;
  final String date;
  final String? time;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final int categoryId;
  final String? categoryName;
  final String? imageUrl;
  final int mealType;
  final String unit;

  DailyNutrition({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.date,
    this.time,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    this.categoryId = 0,
    this.categoryName,
    this.imageUrl,
    this.mealType = 1,
    this.unit = 'หน่วย',
  });

  factory DailyNutrition.fromJson(Map<String, dynamic> json) {
    final nested = json['nutrition'] as Map<String, dynamic>?;
    final foodName = nested?['ntt_food_name'] as String? ??
        json['dntt_custom_food_name'] as String? ??
        json['ntt_food_name'] as String? ??
        'อาหาร';
    final catNested = nested?['category'] as Map<String, dynamic>?;
    final rawImage = nested?['ntt_food_image'] as String? ?? json['dntt_image'] as String?;
    return DailyNutrition(
      id: json['dntt_id'] ?? json['id'] ?? 0,
      foodId: json['ntt_id'] ?? json['food_id'] ?? 0,
      foodName: foodName.isNotEmpty ? foodName : 'อาหาร',
      quantity: (json['dntt_quantity'] ?? json['quantity'] ?? 1).toDouble(),
      date: json['dntt_date'] ?? json['date'] ?? '',
      time: json['dntt_time'] ?? json['time'],
      totalCalories:
          (json['dntt_total_calories'] ?? json['total_calories'] ?? 0).toDouble(),
      totalProtein:
          (json['dntt_total_protein'] ?? json['total_protein'] ?? 0).toDouble(),
      totalCarbs: (json['dntt_total_carb'] ??
              json['dntt_total_carbs'] ??
              json['total_carbs'] ??
              0)
          .toDouble(),
      totalFat: (json['dntt_total_fat'] ?? json['total_fat'] ?? 0).toDouble(),
      categoryId: (nested?['nttc_id'] ?? json['nttc_id'] ?? 0) as int,
      categoryName: catNested?['nttc_name']?.toString()
          ?? nested?['nttc_name']?.toString(),
      imageUrl: ApiClient.prefixPath(rawImage),
      mealType: (json['dntt_meal_type'] ?? json['meal_type'] ?? 1) as int,
      unit: json['dntt_unit']?.toString() ?? json['unit']?.toString() ?? 'หน่วย',
    );
  }
}
