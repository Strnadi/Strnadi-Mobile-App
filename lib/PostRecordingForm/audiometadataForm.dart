import 'package:flutter/material.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';
import 'package:geolocator/geolocator.dart';

class AudioForm extends StatefulWidget {
  const AudioForm({Key? key}) : super(key: key);

  @override
  _AudioFormState createState() => _AudioFormState();
}

class _AudioFormState extends State<AudioForm> {

  final _nameFormTextController = TextEditingController();
  final _commentFormController = TextEditingController();
  // this is the representation of the count of strnadi
  final _scountFormController = TextEditingController();
  final _photoPathController = TextEditingController();

  late Position _coordinates;


  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
  

}