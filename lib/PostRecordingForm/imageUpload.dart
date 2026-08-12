/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

typedef SingleImagePicker = Future<XFile?> Function(ImageSource source);
typedef MultipleImagePicker = Future<List<XFile>> Function();

class MultiPhotoUploadWidget extends StatefulWidget {
  final Function(List<File>) onImagesSelected;
  final SingleImagePicker? pickImage;
  final MultipleImagePicker? pickMultipleImages;

  const MultiPhotoUploadWidget({
    Key? key,
    required this.onImagesSelected,
    this.pickImage,
    this.pickMultipleImages,
  }) : super(key: key);

  @override
  _MultiPhotoUploadWidgetState createState() => _MultiPhotoUploadWidgetState();
}

class _MultiPhotoUploadWidgetState extends State<MultiPhotoUploadWidget> {
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;

  void _setPicking(bool value) {
    if (!mounted || _isPicking == value) return;
    setState(() => _isPicking = value);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking) return;
    _setPicking(true);
    try {
      final XFile? pickedFile = await (widget.pickImage?.call(source) ??
          _picker.pickImage(source: source));
      if (!mounted || pickedFile == null) return;

      setState(() {
        _images.add(File(pickedFile.path));
      });
      widget.onImagesSelected(List<File>.unmodifiable(_images));
    } finally {
      _setPicking(false);
    }
  }

  Future<void> _pickMultipleImages() async {
    if (_isPicking) return;
    _setPicking(true);
    try {
      final List<XFile> pickedFiles =
          await (widget.pickMultipleImages?.call() ?? _picker.pickMultiImage());
      if (!mounted || pickedFiles.isEmpty) return;

      setState(() {
        for (final XFile file in pickedFiles) {
          _images.add(File(file.path));
        }
      });
      widget.onImagesSelected(List<File>.unmodifiable(_images));
    } finally {
      _setPicking(false);
    }
  }

  void _removeImage(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() {
      _images.removeAt(index);
    });
    widget.onImagesSelected(List<File>.unmodifiable(_images));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t('postRecordingForm.imageUpload.title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              t('postRecordingForm.imageUpload.selectedCount')
                  .replaceFirst('{count}', _images.length.toString()),
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Upload buttons row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('photo-upload-camera'),
                onPressed:
                    _isPicking ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 16),
                label: Text(
                    t('postRecordingForm.imageUpload.buttons.takePhoto'),
                    style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('photo-upload-gallery'),
                onPressed: _isPicking ? null : _pickMultipleImages,
                icon: const Icon(Icons.photo_library, size: 16),
                label: Text(t('postRecordingForm.imageUpload.buttons.upload'),
                    style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15),

        // Image grid
        if (_images.isNotEmpty)
          Container(
            height: 120, // Fixed height for the grid
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              itemBuilder: (context, index) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        _images[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        if (_images.isEmpty)
          Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              t('postRecordingForm.imageUpload.placeholders.noImages'),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}
