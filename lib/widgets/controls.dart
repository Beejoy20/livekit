import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dipesh/ApiService/ApiService.dart';
import 'package:dipesh/Model/UserMetaData.dart';
import 'package:dipesh/utils/exts.dart';
import 'package:dipesh/utils/roles.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ControlsWidget extends StatefulWidget {
  //
  final Room room;
  final LocalParticipant participant;
  bool handrise = false;

  ControlsWidget(
    this.room,
    this.participant, {
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  //
  CameraPosition position = CameraPosition.front;
  ApiService apiService = new ApiService();

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;
  MediaDevice? _selectedVideoInput;
  bool handRaise = false;

  StreamSubscription? _subscription;

  UserMetaData? _metadata;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream
        .listen((List<MediaDevice> devices) {
      _loadDevices(devices);
    });
    _metadata = UserMetaData.fromJson(jsonDecode(participant.metadata!));
    Hardware.instance.enumerateDevices().then(_loadDevices);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    participant.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    _selectedVideoInput = _videoInputs?.first;
    setState(() {});
  }

  void _onChange() {
    // trigger refresh
    setState(() {});
  }

  // void _unpublishAll() async {
  //   final result = await context.showUnPublishDialog();
  //   if (result == true) await participant.unpublishAllTracks();
  // }

  void _disableAudio() async {
    await participant.setMicrophoneEnabled(false);
  }

  Future<void> _enableAudio() async {
    await participant.setMicrophoneEnabled(true);
  }

  void _disableVideo() async {
    await participant.setCameraEnabled(false);
  }

  void _enableVideo() async {
    await participant.setCameraEnabled(true);
  }

  void _selectAudioOutput(MediaDevice device) async {
    await Hardware.instance.selectAudioOutput(device);
    setState(() {});
  }

  void _selectAudioInput(MediaDevice device) async {
    await Hardware.instance.selectAudioInput(device);
    setState(() {});
  }

  void _selectVideoInput(MediaDevice device) async {
    final track = participant.videoTracks.firstOrNull?.track;
    if (track == null) return;
    if (_selectedVideoInput?.deviceId != device.deviceId) {
      await track.switchCamera(device.deviceId);
      _selectedVideoInput = device;
      setState(() {});
    }
  }

  void _toggleCamera() async {
    //
    final track = participant.videoTracks.firstOrNull?.track;
    if (track == null) return;

    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() {
        position = newPosition;
      });
    } catch (error) {
      print('could not restart track: $error');
      return;
    }
  }

  void _enableScreenShare() async {
    if (WebRTC.platformIsDesktop) {
      try {
        final source = await showDialog<DesktopCapturerSource>(
          context: context,
          builder: (context) => ScreenSelectDialog(),
        );
        if (source == null) {
          print('cancelled screenshare');
          return;
        }
        print('DesktopCapturerSource: ${source.id}');
        var track = await LocalVideoTrack.createScreenShareTrack(
          ScreenShareCaptureOptions(
            sourceId: source.id,
            maxFrameRate: 15.0,
          ),
        );
        await participant.publishVideoTrack(track);
      } catch (e) {
        print('could not publish video: $e');
      }
      return;
    }
    if (WebRTC.platformIsAndroid) {
      // Android specific;
      try {
        // Required for android screenshare.
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: 'Screen Sharing',
          notificationText: 'Your screen is being shared',
          notificationImportance: AndroidNotificationImportance.Default,
          notificationIcon:
              AndroidResource(name: 'livekit_ic_launcher', defType: 'mipmap'),
        );
        await FlutterBackground.initialize(androidConfig: androidConfig);
        await FlutterBackground.enableBackgroundExecution();
      } catch (e) {
        print('could not publish video: $e');
      }
    }
    await participant.setScreenShareEnabled(true);
  }

  void _disableScreenShare() async {
    await participant.setScreenShareEnabled(false);
    if (Platform.isAndroid) {
      // Android specific
      try {
        //   await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        print('error disabling screen share: $error');
      }
    }
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  void _onTapReconnect() async {
    final result = await context.showReconnectDialog();
    if (result == true) {
      try {
        await widget.room.reconnect();
        await context.showReconnectSuccessDialog();
      } catch (error) {
        await context.showErrorDialog(error);
      }
    }
  }

  void _onTapUpdateSubscribePermission() async {
    final result = await context.showSubscribePermissionDialog();
    if (result != null) {
      try {
        widget.room.localParticipant?.setTrackSubscriptionPermissions(
          allParticipantsAllowed: result,
        );
      } catch (error) {
        await context.showErrorDialog(error);
      }
    }
  }

  bool isStudent() {
    return _metadata?.roles!.indexOf(Roles.student.name) != -1;
  }

  void _raiseHand() async {
    setState(() {
      handRaise = true;
    });
    handRaise = !handRaise;

    Fluttertoast.showToast(
        msg:
            "You raised your hand! We will let the moderators know you want to talk...",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
        timeInSecForIosWeb: 2,
        backgroundColor: Colors.white,
        textColor: Colors.black,
        fontSize: 14.0);

    await apiService.updateMetadata(_metadata!.userId!, participant.room.name!,
        participant.identity, handRaise);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (isStudent())
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _raiseHand,
                child: IconButton(
                  onPressed: _raiseHand,
                  icon: Icon(
                    Icons.back_hand_outlined,
                    color: handRaise ? Colors.white : Colors.purple[700],
                  ),
                  tooltip: 'Raise Hand',
                ),
                shape: const CircleBorder(),
                fillColor: handRaise ? Colors.purple[800] : Colors.grey[200],
              ),
            ),
          const SizedBox(width: 3),
          if (participant.permissions.canPublish)
            if (participant.isMicrophoneEnabled())
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _disableAudio,
                child: IconButton(
                  onPressed: _disableAudio,
                  icon: const Icon(Icons.mic_none, color: Colors.white),
                  tooltip: 'Mute Mic',
                ),
                shape: const CircleBorder(),
                elevation: 1.0,
                fillColor: Colors.red,
              )
            else
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _enableAudio,
                child: IconButton(
                  onPressed: _enableAudio,
                  icon: const Icon(
                    Icons.mic_off,
                    color: Colors.white,
                  ),
                  tooltip: 'Unmute Mic',
                ),
                shape: const CircleBorder(),
                elevation: 1.0,
                fillColor: Colors.red,
              ),
          const SizedBox(width: 3),
          if (participant.permissions.canPublish)
            if (participant.isCameraEnabled())
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _disableVideo,
                child: IconButton(
                  onPressed: _disableVideo,
                  icon: const Icon(
                    EvaIcons.video,
                    color: Colors.white,
                  ),
                  tooltip: 'Mute Video',
                ),
                shape: const CircleBorder(),
                fillColor: Colors.red,
              )
            else
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _enableVideo,
                child: IconButton(
                  onPressed: _enableVideo,
                  icon: const Icon(
                    EvaIcons.videoOffOutline,
                    color: Colors.white,
                  ),
                  tooltip: 'Unmute video',
                ),
                shape: const CircleBorder(),
                elevation: 1.0,
                fillColor: Colors.red,
              ),
          const SizedBox(width: 3),
          if (participant.permissions.canPublishData && !isStudent())
            if (participant.isScreenShareEnabled())
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _disableScreenShare,
                child: IconButton(
                  onPressed: _disableScreenShare,
                  icon: const Icon(
                    Icons.share,
                    color: Colors.white,
                  ),
                  tooltip: 'Unshare screen',
                ),
                shape: const CircleBorder(),
                fillColor: Colors.red,
              )
            else
              RawMaterialButton(
                constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
                onPressed: _enableScreenShare,
                child: IconButton(
                  onPressed: _enableScreenShare,
                  icon: const Icon(
                    Icons.monitor,
                    color: Colors.white,
                  ),
                  tooltip: 'Share screen',
                ),
                shape: const CircleBorder(),
                fillColor: Colors.red,
              ),
          const SizedBox(width: 3),
          RawMaterialButton(
            constraints: const BoxConstraints(maxWidth: 40, maxHeight: 40),
            onPressed: _onTapDisconnect,
            child: IconButton(
              onPressed: _onTapDisconnect,
              icon: const Icon(
                Icons.call_end,
                color: Colors.white,
              ),
              tooltip: 'Disconnect',
            ),
            shape: const CircleBorder(),
            fillColor: Colors.red,
          ),
        ],
      ),
    );
  }
}
