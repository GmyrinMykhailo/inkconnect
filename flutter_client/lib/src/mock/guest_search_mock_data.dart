import '../screens/guest_dashboard_screen.dart';

const String guestTattooCategory = 'Тату мастера';
const String guestPiercingCategory = 'Мастера пирсинга';

const List<String> guestTattooStyles = [
  'Реализм',
  'Япония',
  'Леттеринг',
  'Ньюскул',
  'Графика / Гравюра',
  'Биомеханика / Биоорганика',
  'Орнаментал / Геометрия',
  'Олд Скул',
  'Авторский',
];

const List<String> guestPiercingStyles = [
  'Пирсинг Хеликс',
  'Пирсинг Конч',
  'Пирсинг Дейс',
  'Пирсинг Руук',
  'Пирсинг Трагус',
  'Пирсинг Индастриал',
  'Пирсинг Форвард хеликс',
  'Пирсинг Антитрагус',
  'Пирсинг Снаг',
  'Пирсинг Крыла носа',
  'Пирсинг Септум',
  'Пирсинг Микродермал',
  'Пирсинг Пупка',
  'Пирсинг Смайл',
  'Пирсинг Медуза',
  'Пирсинг Бридж',
  'Пирсинг Соска',
];

class GuestMasterSearchItem {
  const GuestMasterSearchItem({
    this.id = '',
    required this.username,
    required this.name,
    required this.city,
    required this.rating,
    required this.reviewCount,
    required this.priceLabel,
    required this.priceValue,
    required this.tags,
    required this.description,
    required this.assetPath,
    this.avatarUrl = '',
    this.showFullName = true,
    this.studioName = '',
    this.isFavorite = false,
  });

  final String id;
  final String username;
  final String name;
  final String city;
  final double rating;
  final int reviewCount;
  final String priceLabel;
  final int priceValue;
  final List<String> tags;
  final String description;
  final String assetPath;
  final String avatarUrl;
  final bool showFullName;
  final String studioName;
  final bool isFavorite;

  String get ratingLabel =>
      '${rating.toString().replaceAll('.0', '')} ($reviewCount)';

  String get handle => username.startsWith('@') ? username : '@$username';

  GuestMasterSearchItem copyWith({bool? isFavorite}) {
    return GuestMasterSearchItem(
      id: id,
      username: username,
      name: name,
      city: city,
      rating: rating,
      reviewCount: reviewCount,
      priceLabel: priceLabel,
      priceValue: priceValue,
      tags: tags,
      description: description,
      assetPath: assetPath,
      avatarUrl: avatarUrl,
      showFullName: showFullName,
      studioName: studioName,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

const List<GuestMasterSearchItem> guestTattooMasters = [
  GuestMasterSearchItem(
    username: 'master',
    name: 'Мария Козлова',
    city: 'Москва',
    rating: 5.0,
    reviewCount: 203,
    priceLabel: 'от 10 000 ₽',
    priceValue: 10000,
    tags: ['Япония', 'Леттеринг'],
    description: 'Мастер акварельных татуировок с нежными цветочными мотивами.',
    assetPath: GuestDashboardAssets.maria,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'blackline.tattoo',
    name: 'Анна Петрова',
    city: 'Москва',
    rating: 4.9,
    reviewCount: 127,
    priceLabel: 'от 8 000 ₽',
    priceValue: 8000,
    tags: ['Реализм', 'Графика / Гравюра'],
    description:
        'Специализируюсь на реалистичных портретах и черно-белых работах.\nОпыт работы более 8 лет.',
    assetPath: GuestDashboardAssets.anna,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'ornament.smirnov',
    name: 'Игорь Смирнов',
    city: 'Москва',
    rating: 4.8,
    reviewCount: 95,
    priceLabel: 'от 6 000 ₽',
    priceValue: 6000,
    tags: ['Орнаментал / Геометрия', 'Биомеханика / Биоорганика'],
    description:
        'Создаю уникальные геометрические композиции и работаю в стилях биомеханика и биоорганика.',
    assetPath: GuestDashboardAssets.dmitry,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'oldschool.lebedev',
    name: 'Дмитрий Лебедев',
    city: 'Москва',
    rating: 4.7,
    reviewCount: 84,
    priceLabel: 'от 7 000 ₽',
    priceValue: 7000,
    tags: ['Олд Скул', 'Ньюскул'],
    description:
        'Работаю в классических стилях олд скул и ньюскул с яркими, выразительными сюжетами.',
    assetPath: GuestDashboardAssets.alexander,
    showFullName: false,
  ),
];

const List<GuestMasterSearchItem> guestPiercingMasters = [
  GuestMasterSearchItem(
    username: 'piercing.vika',
    name: 'Виктория Белова',
    city: 'Москва',
    rating: 5.0,
    reviewCount: 198,
    priceLabel: 'от 2 800 ₽',
    priceValue: 2800,
    tags: ['Пирсинг губы', 'Пирсинг Монро', 'Пирсинг Медуза', 'Пирсинг Смайл'],
    description: 'Работаю с пирсингом губ и полости рта. Опыт более 10 лет.',
    assetPath: GuestDashboardAssets.maria,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'helix.elena',
    name: 'Елена Соколова',
    city: 'Москва',
    rating: 4.9,
    reviewCount: 156,
    priceLabel: 'от 2 500 ₽',
    priceValue: 2500,
    tags: ['Пирсинг Хеликс', 'Пирсинг Конч', 'Пирсинг Трагус'],
    description:
        'Специализируюсь на ушных пирсингах. Работаю только с титановыми украшениями высшего качества.',
    assetPath: GuestDashboardAssets.anna,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'novikov.piercing',
    name: 'Александр Новиков',
    city: 'Москва',
    rating: 4.8,
    reviewCount: 142,
    priceLabel: 'от 3 000 ₽',
    priceValue: 3000,
    tags: ['Пирсинг Септум', 'Пирсинг Крыла носа', 'Пирсинг Бридж'],
    description:
        'Мастер по пирсингу носа. Индивидуальный подбор украшений под анатомию лица.',
    assetPath: GuestDashboardAssets.dmitry,
    showFullName: true,
  ),
  GuestMasterSearchItem(
    username: 'max.microdermal',
    name: 'Максим Орлов',
    city: 'Москва',
    rating: 4.7,
    reviewCount: 89,
    priceLabel: 'от 3 500 ₽',
    priceValue: 3500,
    tags: ['Пирсинг Пупка', 'Пирсинг Соска', 'Пирсинг Микродермал'],
    description:
        'Специализируюсь на сложных видах пирсинга. Работаю в стерильных условиях.',
    assetPath: GuestDashboardAssets.alexander,
    showFullName: false,
  ),
];
