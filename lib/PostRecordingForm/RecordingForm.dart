import 'package:flutter/material.dart';
import 'package:strnadi/AudioSpectogram/audioRecorder.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:latlong2/latlong.dart';

import '../AudioSpectogram/editor.dart';

class RecordingForm extends StatefulWidget {
  final String filepath;

  const RecordingForm({Key? key, required this.filepath}) : super(key: key);

  @override
  _RecordingFormState createState() => _RecordingFormState();
}

class _RecordingFormState extends State<RecordingForm> {
  final _recordingNameController = TextEditingController();
  final _commentController = TextEditingController();
  double _strnadiCountController = 1.0;
  final _photoPathController = TextEditingController();
  LatLng? _currentPosition;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height - kToolbarHeight - kBottomNavigationBarHeight,
      ),
      child: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              //Spectogram(audioFilePath: widget.filepath),
              const SizedBox(height: 50),
              Form(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextFormField(
                        controller: _recordingNameController,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Nazev Nahravky',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        textAlign: TextAlign.center,
                        controller: _commentController,
                        decoration: const InputDecoration(
                          labelText: 'Komentar',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      Slider(
                        value: _strnadiCountController,
                        min: 1,
                        max: 3,
                        divisions: 2,
                        label: "Pocet Strnadi",
                        onChanged: (value) {
                          setState(() {
                            _strnadiCountController = value;
                          });
                        },
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}