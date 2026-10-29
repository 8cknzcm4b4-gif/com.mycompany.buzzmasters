/// Cosmetic shop: catalogue, item detail, inventory.
///
/// Every price on screen comes from the store through the controller. When the
/// store is not connected the card says so instead of showing a number.
library;

import 'package:flutter/material.dart';

import '../../design/bm_theme.dart';
import '../../widgets/bm_button.dart';
import '../../widgets/bm_panel.dart';
import '../../widgets/studio_background.dart';
import '../bootstrap.dart';
import '../controller.dart';
import '../models.dart';

const _categoryOrder = <ShopCategory>[
  ShopCategory.bundles,
  ShopCategory.avatars,
  ShopCategory.profileFrames,
  ShopCategory.racingTrails,
  ShopCategory.celebrations,
  ShopCategory.nameplates,
  ShopCategory.vipExclusive,
];

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ShopCategory _filter = ShopCategory.bundles;

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final items = [
          for (final item in ShopCatalog.items)
            if (item.category == _filter) item,
        ];
        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'COSMETIC SHOP',
                      textAlign: TextAlign.center,
                      style: BmText.display(18, color: BmColors.gold),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Style your racer. Owned items stay yours.',
                textAlign: TextAlign.center,
                style: BmText.body(12),
              ),
              const SizedBox(height: 12),
              BmStatusBanner(controller: controller),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categoryOrder.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = _categoryOrder[index];
                    final selected = category == _filter;
                    return ChoiceChip(
                      label: Text(category.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = category),
                      labelStyle: BmText.label(10,
                          color: selected
                              ? const Color(0xFF00212B)
                              : Colors.white),
                      selectedColor: BmColors.cyan,
                      backgroundColor: BmColors.panel,
                      side: BorderSide(
                        color: selected
                            ? BmColors.cyan
                            : BmColors.panelEdge.withValues(alpha: 0.9),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(19),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('BALANCE', style: BmText.label(10)),
                  const SizedBox(width: 8),
                  Text(
                    '${controller.coins} coins',
                    style: BmText.title(13, color: BmColors.gold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InventoryScreen(),
                      ),
                    ),
                    child: Text(
                      'MY INVENTORY',
                      style: BmText.label(10, color: BmColors.cyan),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing here yet.',
                          style: BmText.body(13, color: BmColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _ShopItemCard(item: items[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    final controller = BmMonetisation.instance;
    final owned = controller.inventory.owns(item.id);
    final equipped = controller.inventory.equipped[item.category] == item.id;
    final product = item.isBundle
        ? controller.productFor(item.bundleProductIds.first)
        : null;
    final accent = Color(item.previewColor);

    final String priceLabel;
    if (owned) {
      priceLabel = 'OWNED';
    } else if (!item.isBundle) {
      priceLabel = item.vipOnly ? 'VIP' : 'FREE';
    } else if (product == null) {
      priceLabel = 'Store not connected';
    } else if (!product.hasPrice) {
      priceLabel = 'Unavailable';
    } else {
      priceLabel = product.priceString;
    }

    return BmPanel(
      color: accent,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
              border: Border.all(color: accent, width: 1.4),
            ),
            child: Icon(
              item.previewIcon == null
                  ? Icons.auto_awesome_rounded
                  : IconData(item.previewIcon!, fontFamily: 'MaterialIcons'),
              color: accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: BmText.title(14)),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.body(11, color: BmColors.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  priceLabel,
                  style: BmText.label(10, color: BmColors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: owned
                ? BmButton(
                    label: equipped ? 'EQUIPPED' : 'EQUIP',
                    height: 40,
                    fontSize: 12,
                    style: equipped ? BmButtonStyle.outline : BmButtonStyle.cyan,
                    onPressed: equipped
                        ? () => controller.unequip(item.category)
                        : () => controller.equip(item),
                  )
                : BmButton(
                    label: 'DETAILS',
                    height: 40,
                    fontSize: 12,
                    style: BmButtonStyle.gold,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: BmColors.midnight,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => ItemDetailsSheet(item: item),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Item detail with preview, price, purchase confirmation and failure feedback.
class ItemDetailsSheet extends StatefulWidget {
  const ItemDetailsSheet({super.key, required this.item});

  final ShopItem item;

  @override
  State<ItemDetailsSheet> createState() => _ItemDetailsSheetState();
}

class _ItemDetailsSheetState extends State<ItemDetailsSheet> {
  bool _working = false;

  Future<void> _buy(MonetisationController controller) async {
    final blocker = controller.blockReasonFor(widget.item);
    if (blocker != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(blocker)));
      return;
    }
    setState(() => _working = true);
    final product = controller.productFor(
        widget.item.bundleProductIds.first);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.midnight,
        title: Text('Buy ${widget.item.name}?',
            style: BmText.title(15, color: Colors.white)),
        content: Text(
          product == null
              ? 'The store has not returned a price for this item.'
              : 'Price: ${product.priceString}. You will confirm with your store.',
          style: BmText.body(12, color: BmColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _working = false);
      return;
    }
    await controller.buyBundle(widget.item.bundleProductIds.first);
    if (mounted) setState(() => _working = false);
    if (mounted && controller.purchaseState == PurchaseState.success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = BmMonetisation.instance;
    final owned = controller.inventory.owns(widget.item.id);
    final product = widget.item.isBundle
        ? controller.productFor(widget.item.bundleProductIds.first)
        : null;
    final accent = Color(widget.item.previewColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.55), accent],
                ),
                boxShadow: bmGlow(accent, blur: 26, opacity: 0.5),
              ),
              child: Icon(
                widget.item.previewIcon == null
                    ? Icons.auto_awesome_rounded
                    : IconData(widget.item.previewIcon!,
                        fontFamily: 'MaterialIcons'),
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(widget.item.name,
                style: BmText.display(18, color: Colors.white)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              widget.item.category.label,
              style: BmText.label(10, color: accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(widget.item.description, style: BmText.body(13)),
          const SizedBox(height: 16),
          if (owned) ...[
            BmButton(
              label: 'OWNED — EQUIP',
              style: BmButtonStyle.cyan,
              onPressed: () {
                controller.equip(widget.item);
                Navigator.of(context).pop();
              },
            ),
          ] else ...[
            Text(
              product == null
                  ? 'Store not connected'
                  : product.hasPrice
                      ? 'Price: ${product.priceString}'
                      : 'Price unavailable from the store',
              style: BmText.title(13, color: BmColors.gold),
            ),
            const SizedBox(height: 12),
            BmButton(
              label: _working ? 'CONTACTING STORE…' : 'BUY',
              style: BmButtonStyle.gold,
              onPressed: _working ? null : () => _buy(controller),
            ),
            if (controller.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(controller.message,
                  style: BmText.body(11, color: BmColors.muted)),
            ],
          ],
        ],
      ),
    );
  }
}

/// Everything the player owns, grouped by slot, with equip/unequip.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MonetisationScope(
      builder: (context, controller) {
        final owned = [
          for (final item in ShopCatalog.items)
            if (controller.inventory.owns(item.id)) item,
        ];
        return StudioScaffold(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'MY INVENTORY',
                      textAlign: TextAlign.center,
                      style: BmText.display(18, color: BmColors.cyan),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              BmStatusBanner(controller: controller),
              Expanded(
                child: owned.isEmpty
                    ? Center(
                        child: Text(
                          'No cosmetics yet — visit the shop.',
                          style: BmText.body(13, color: BmColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: owned.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = owned[index];
                          final equipped =
                              controller.inventory.equipped[item.category] ==
                                  item.id;
                          return BmPanel(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  item.previewIcon == null
                                      ? Icons.auto_awesome_rounded
                                      : IconData(item.previewIcon!,
                                          fontFamily: 'MaterialIcons'),
                                  color: Color(item.previewColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name, style: BmText.title(13)),
                                      Text(
                                        item.category.label,
                                        style: BmText.label(9,
                                            color: BmColors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: BmButton(
                                    label: equipped ? 'UNEQUIP' : 'EQUIP',
                                    height: 38,
                                    fontSize: 11,
                                    style: equipped
                                        ? BmButtonStyle.outline
                                        : BmButtonStyle.cyan,
                                    onPressed: () => equipped
                                        ? controller.unequip(item.category)
                                        : controller.equip(item),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
