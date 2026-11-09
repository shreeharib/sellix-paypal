import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// One thing sellix stops and asks the merchant about.
class ObAsk {
  const ObAsk(this.icon, this.title, this.detail, {this.isBulk = false});

  final IconData icon;
  final String title;
  final String detail;
  final bool isBulk;
}

/// What a kind of shop sells: the words and questions of the rules step. Only wording: no sample
/// products, customers or numbers presented as real. (The stock step's wording comes from the
/// backend's product schema.)
class ObCategory {
  const ObCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.examples,
    required this.unit,
    required this.customLabel,
    required this.customDetail,
    required this.bulkLimit,
    required this.ownAsks,
    required this.never,
  });

  final String id;
  final String label;
  final IconData icon;
  final String examples;
  final String unit;
  final String customLabel;
  final String customDetail;
  final int bulkLimit;
  final List<ObAsk> ownAsks;
  final List<String> never;

  /// The usual questions, then this kind of shop's own.
  List<ObAsk> get asks => [
    const ObAsk(TablerIcons.discount, 'Discounts and bargaining', 'sellix never gives a discount alone'),
    const ObAsk(TablerIcons.stack_2, 'Bulk orders', 'Above the size you set', isBulk: true),
    ObAsk(TablerIcons.pencil, customLabel, customDetail),
    const ObAsk(TablerIcons.mood_sad, 'Complaints and refunds', 'You decide every refund'),
    const ObAsk(TablerIcons.map_pin_off, 'Delivery outside your area', 'Places you do not usually send to'),
    ...ownAsks,
  ];
}

const obCategories = [
  ObCategory(
    id: 'fashion',
    label: 'Clothing',
    icon: TablerIcons.hanger,
    examples: 'Kurtis, sarees, tops',
    unit: 'pieces',
    customLabel: 'Custom stitching',
    customDetail: 'Blouse stitching, alterations, photos of a design',
    bulkLimit: 10,
    ownAsks: [
      ObAsk(TablerIcons.ruler_measure, 'Size and fit questions', 'When your size chart does not answer it'),
      ObAsk(TablerIcons.arrows_exchange, 'Exchanges and returns', 'Wrong size, changed mind'),
    ],
    never: ['Exchanges', 'Delivery times', 'Colour match to a photo', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'footwear',
    label: 'Shoes',
    icon: TablerIcons.shoe,
    examples: 'Sandals, sneakers, heels',
    unit: 'pairs',
    customLabel: 'Custom size',
    customDetail: 'Sizes you do not stock, wedding pairs',
    bulkLimit: 6,
    ownAsks: [
      ObAsk(TablerIcons.ruler_measure, 'Size and fit questions', 'When your size chart does not answer it'),
      ObAsk(TablerIcons.arrows_exchange, 'Exchanges and returns', 'Wrong size, worn shoes'),
      ObAsk(TablerIcons.cash, 'Cash on delivery', 'If you take it only sometimes'),
    ],
    never: ['Exchanges', 'Delivery times', 'Cash on delivery', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'food',
    label: 'Food and sweets',
    icon: TablerIcons.cake,
    examples: 'Cakes, snacks, home food',
    unit: 'pieces',
    customLabel: 'Custom order',
    customDetail: 'Photos, tiers, messages on cakes',
    bulkLimit: 30,
    ownAsks: [
      ObAsk(TablerIcons.alert_triangle, 'Allergy and diet questions', 'Eggless, nut-free, sugar-free, Jain'),
      ObAsk(TablerIcons.calendar_event, 'Orders for a later date', 'Anything not for today'),
    ],
    never: ['Same-day custom orders', 'Delivery times', 'Sugar-free', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'beauty',
    label: 'Beauty and skincare',
    icon: TablerIcons.droplet,
    examples: 'Face oils, serums, kits',
    unit: 'pieces',
    customLabel: 'Custom gift set',
    customDetail: 'Gift sets, return gifts, your label',
    bulkLimit: 20,
    ownAsks: [
      ObAsk(TablerIcons.alert_triangle, 'Allergy and skin questions', 'Reactions, pregnancy, sensitive skin'),
      ObAsk(TablerIcons.shield_check, 'Is it original?', 'Ingredients, certificates, batch dates'),
    ],
    never: ['Medical advice', 'Results in days', 'Delivery times', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'jewellery',
    label: 'Jewellery and accessories',
    icon: TablerIcons.diamond,
    examples: 'Earrings, chains, bangles',
    unit: 'pieces',
    customLabel: 'Custom design',
    customDetail: 'Names, photos of a design, your own stones',
    bulkLimit: 15,
    ownAsks: [
      ObAsk(TablerIcons.shield_check, 'Is it real?', 'Hallmark, certificates, purity'),
      ObAsk(TablerIcons.arrows_exchange, 'Returns and exchanges', 'Earrings are often no-return'),
    ],
    never: ['Purity without a bill', 'Delivery times', 'Lifetime polish', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'home',
    label: 'Home and decor',
    icon: TablerIcons.lamp,
    examples: 'Cushions, candles, wall art',
    unit: 'pieces',
    customLabel: 'Custom size',
    customDetail: 'Sizes, colours, fabric you choose',
    bulkLimit: 10,
    ownAsks: [
      ObAsk(TablerIcons.package_off, 'Damaged in delivery', 'Cracks, breakage, missing parts'),
      ObAsk(TablerIcons.arrows_exchange, 'Returns and exchanges', 'Colour looks different at home'),
    ],
    never: ['Safe delivery of glass', 'Delivery times', 'Exact colour match', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'handmade',
    label: 'Handmade and gifts',
    icon: TablerIcons.gift,
    examples: 'Hampers, crochet, resin',
    unit: 'pieces',
    customLabel: 'Personalised order',
    customDetail: 'Names, photos, messages on the gift',
    bulkLimit: 20,
    ownAsks: [
      ObAsk(TablerIcons.clock, 'Rush orders', 'Anything needed sooner than you can make it'),
      ObAsk(TablerIcons.photo, 'Designs from a photo', 'Customers ask you to copy a design'),
    ],
    never: ['Exact copy of a design', 'Delivery times', 'Same-day gifts', 'Free delivery', 'Discounts'],
  ),
  ObCategory(
    id: 'plants',
    label: 'Plants and flowers',
    icon: TablerIcons.plant_2,
    examples: 'Pots, saplings, bouquets',
    unit: 'plants',
    customLabel: 'Events and custom setups',
    customDetail: 'Events, garlands, balcony setups',
    bulkLimit: 25,
    ownAsks: [
      ObAsk(TablerIcons.leaf, 'Plant care and sick plants', 'Yellow leaves, pests, plant died'),
      ObAsk(TablerIcons.seeding, 'Replacements', 'You decide if a plant is replaced'),
    ],
    never: ['A plant will survive', 'Delivery times', 'Pet safe without checking', 'Free delivery', 'Discounts'],
  ),
  obOtherCategory,
];

const obOtherCategory = ObCategory(
  id: 'other',
  label: 'Other',
  icon: TablerIcons.dots,
  examples: 'Tell us what you sell',
  unit: 'pieces',
  customLabel: 'Custom order',
  customDetail: 'Anything not in your product list',
  bulkLimit: 15,
  ownAsks: [ObAsk(TablerIcons.arrows_exchange, 'Returns and exchanges', 'Changed mind, wrong item')],
  never: ['Exchanges', 'Delivery times', 'Same-day delivery', 'Free delivery', 'Discounts'],
);

/// The saved answer is the words the agent reads ("Food and sweets", or what the merchant typed).
/// Null when nothing is saved; anything unknown counts as Other.
ObCategory? obCategoryOf(String? saved) {
  final text = saved?.trim() ?? '';
  if (text.isEmpty) return null;
  for (final c in obCategories) {
    if (c.id != obOtherCategory.id && (c.label == text || c.id == text)) return c;
  }
  return obOtherCategory;
}
