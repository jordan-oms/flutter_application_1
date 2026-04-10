// lib/widgets/date_time_picker.dart

import 'package:flutter/material.dart';

class ProfessionalDateTimePicker {
  static Future<DateTime?> selectDateTime(
    BuildContext context, {
    DateTime? initialDateTime,
  }) async {
    initialDateTime ??= DateTime.now();

    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return _DateTimePickerDialog(initialDateTime: initialDateTime!);
      },
    );
  }
}

class _DateTimePickerDialog extends StatefulWidget {
  final DateTime initialDateTime;

  const _DateTimePickerDialog({
    required this.initialDateTime,
  });

  @override
  State<_DateTimePickerDialog> createState() => _DateTimePickerDialogState();
}

class _DateTimePickerDialogState extends State<_DateTimePickerDialog> {
  late DateTime selectedDate;
  late int selectedHour;
  late int selectedMinute;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDateTime;
    selectedHour = widget.initialDateTime.hour;
    selectedMinute = widget.initialDateTime.minute;
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  String _formatTime(int hour, int minute) {
    return "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sélectionner date et heure',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),

              // Section Date
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DATE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 1)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          locale: const Locale('fr', 'FR'),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                datePickerTheme: DatePickerThemeData(
                                  headerBackgroundColor: Colors.blue.shade600,
                                  headerForegroundColor: Colors.white,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDate(selectedDate),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                            ),
                            Icon(
                              Icons.calendar_today_outlined,
                              color: Colors.blue.shade600,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Section Heure
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HEURE (FORMAT 24H)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Heure
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'HEURE',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedHour =
                                                (selectedHour - 1 + 24) % 24;
                                          });
                                        },
                                        icon: const Icon(Icons.remove),
                                        tooltip: 'Diminuer',
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        selectedHour.toString().padLeft(2, '0'),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 28,
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedHour =
                                                (selectedHour + 1) % 24;
                                          });
                                        },
                                        icon: const Icon(Icons.add),
                                        tooltip: 'Augmenter',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Séparateur
                        Text(
                          ':',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                        ),
                        const SizedBox(width: 12),
                        // Minutes
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'MINUTES',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedMinute =
                                                (selectedMinute - 5 + 60) % 60;
                                          });
                                        },
                                        icon: const Icon(Icons.remove),
                                        tooltip: 'Diminuer',
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        selectedMinute
                                            .toString()
                                            .padLeft(2, '0'),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 28,
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                    Expanded(
                                      child: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            selectedMinute =
                                                (selectedMinute + 5) % 60;
                                          });
                                        },
                                        icon: const Icon(Icons.add),
                                        tooltip: 'Augmenter',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Affichage du résumé
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'Sélection actuelle',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatDate(selectedDate)} à ${_formatTime(selectedHour, selectedMinute)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Boutons d'action
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final result = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedHour,
                        selectedMinute,
                      );
                      Navigator.pop(context, result);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Confirmer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
