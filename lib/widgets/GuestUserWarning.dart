import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/authorizator.dart';
import '../localization/localization.dart';

class GuestUserRules extends StatelessWidget {
  const GuestUserRules({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // tell the user that in guest mode he can view map and record but cannot send them unless he creates an account with cupertino
    return CupertinoAlertDialog(
      title: Text(t('widgets.guest_user_rules.title')),
      content: Text(t('widgets.guest_user_rules.content')),
      actions: [
        CupertinoDialogAction(
          child: Text(t('widgets.guest_user_rules.ok')),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        CupertinoDialogAction(
          child: Text(t('widgets.guest_user_rules.login')),
          onPressed: () async {
            Navigator.of(context).pop();
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setBool('popupShown', false);
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    Authorizator(),
                settings: const RouteSettings(name: '/'),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          },
        ),
      ],
    );
  }
}
