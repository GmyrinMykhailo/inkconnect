import 'package:flutter/material.dart';

import '../city/city_catalog.dart';

class CityAutocompleteField extends StatefulWidget {
  const CityAutocompleteField({
    super.key,
    required this.controller,
    required this.selectedOption,
    required this.onSelected,
    this.onChanged,
    this.labelText = 'Город',
    this.hintText = 'Начните вводить город',
    this.isRequired = false,
    this.enabled = true,
    this.errorText,
    this.maxSuggestions = 10,
  });

  final TextEditingController controller;
  final CityOption? selectedOption;
  final ValueChanged<CityOption?> onSelected;
  final VoidCallback? onChanged;
  final String labelText;
  final String hintText;
  final bool isRequired;
  final bool enabled;
  final String? errorText;
  final int maxSuggestions;

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  late final FocusNode _focusNode;

  bool _loading = true;
  String? _loadError;
  bool _visited = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    _loadCities();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      await CityCatalog.instance.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = null;
      });
      _syncExistingValue();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = 'Не удалось загрузить список городов';
      });
    }
  }

  void _syncExistingValue() {
    final value = widget.controller.text.trim();
    if (value.isEmpty || widget.selectedOption?.displayName == value) {
      return;
    }
    final option = CityCatalog.instance.findByDisplayName(value);
    if (option != null) {
      widget.onSelected(option);
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() {
        _visited = true;
      });
    }
  }

  Iterable<_CityAutocompleteItem> _optionsFor(TextEditingValue value) {
    final query = value.text.trim();
    if (query.isEmpty) {
      return const <_CityAutocompleteItem>[];
    }
    if (_loading) {
      return const [
        _CityAutocompleteItem.message('Загружаем города...'),
      ];
    }
    if (_loadError != null) {
      return [_CityAutocompleteItem.message(_loadError!)];
    }

    final matches = CityCatalog.instance.search(
      query,
      limit: widget.maxSuggestions,
    );
    if (matches.isEmpty) {
      return const [
        _CityAutocompleteItem.message('Ничего не найдено'),
      ];
    }
    return matches.map(_CityAutocompleteItem.city);
  }

  String? _validator(String? value) {
    final text = value?.trim() ?? '';
    if (_loadError != null) {
      return _loadError;
    }
    if (text.isEmpty) {
      return widget.isRequired ? 'Укажите город' : null;
    }
    final selected = widget.selectedOption;
    if (selected == null || selected.displayName != text) {
      return 'Выберите город из списка';
    }
    return null;
  }

  String? _fieldErrorText() {
    if (widget.errorText != null) {
      return widget.errorText;
    }
    if (!_visited || _focusNode.hasFocus) {
      return null;
    }
    return _validator(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<_CityAutocompleteItem>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option.label,
      optionsBuilder: _optionsFor,
      onSelected: (item) {
        final city = item.city;
        if (city == null) {
          return;
        }
        widget.controller.text = city.displayName;
        widget.onSelected(city);
        widget.onChanged?.call();
        setState(() {
          _visited = false;
        });
      },
      fieldViewBuilder: (
        context,
        controller,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            errorText: _fieldErrorText(),
          ),
          onChanged: (value) {
            final selected = widget.selectedOption;
            if (selected != null && selected.displayName != value.trim()) {
              widget.onSelected(null);
            }
            widget.onChanged?.call();
            setState(() {});
          },
          validator: _validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList(growable: false);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final maxWidth = screenWidth < 452 ? screenWidth - 32 : 420.0;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: 280,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    onTap: item.city == null ? null : () => onSelected(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: item.city == null
                              ? const Color(0xFF6E6A66)
                              : const Color(0xFF152033),
                          fontWeight: item.city == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CityAutocompleteItem {
  _CityAutocompleteItem.city(CityOption city)
      : city = city,
        label = city.displayName;

  const _CityAutocompleteItem.message(this.label) : city = null;

  final CityOption? city;
  final String label;
}
