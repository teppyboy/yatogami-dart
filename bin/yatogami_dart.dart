import 'dart:io' show Platform;
import "dart:async";
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commander/nyxx_commander.dart';

const defaultPrefix = "y!";

FutureOr<String?> prefixHandler(IMessage message) {
  return defaultPrefix;
}

List<Future<IUser>> getUsersFromMessage(ICommandContext context, String msg) {
  final args = msg.split(" ");
  args.removeAt(0); // Remove the command from args
  if (args.isEmpty) {
    return List<Future<IUser>>.unmodifiable(
        [Future<IUser>.value(context.author as IUser)]);
  }
  final users = List<Future<IUser>>.empty(growable: true);
  for (final arg in args) {
    var userId = int.tryParse(arg);
    userId ??= int.tryParse(arg.substring(2, arg.length - 1));
    if (userId == null) {
      continue;
    }
    users.add(context.client.fetchUser(Snowflake(userId)));
  }
  return users;
}

Future<IUser> getUserFromMessage(ICommandContext context, String msg) {
  return getUsersFromMessage(context, msg).first;
}

// This code is so broken bro
Future<IMember>? getMemberFromMessage(ICommandContext context, String msg) {
  final guild = context.guild;
  if (guild == null) {
    return null;
  }
  final args = msg.split(" ");
  print(args);
  if (args.length < 2) {
    return Future<IMember>.value(context.member);
  }
  final userIdStr = args[1];
  final userId = int.tryParse(userIdStr.substring(2, userIdStr.length - 1));
  if (userId == null) {
    return Future<IMember>.value(context.member);
  } else {
    return guild.fetchMember(Snowflake(userId));
  }
}

void _avatar(ICommandContext context, String message) async {
  final users = context.message.mentions;
  var user = await getUserFromMessage(context, message);
  if (users.isNotEmpty) {
    user = await users.first.getOrDownload();
  }
  final embed = MessageBuilder.embed(EmbedBuilder()
    ..addAuthor((author) {
      author.name = user.username + "'s avatar";
      author.iconUrl = user.avatarURL(size: 4096);
    })
    ..color = DiscordColor.magenta
    ..imageUrl = user.avatarURL(size: 4096));
  context.reply(embed, reply: true, mention: false);
}

void _ping(ICommandContext context, String message) {
  context.reply(MessageBuilder.content("Pong!"), reply: true, mention: false);
}

void main(List<String> arguments) async {
  var token = Platform.environment["DISCORD_TOKEN"];
  if (token == null) {
    print("DISCORD_TOKEN environment variable is not set.");
    return;
  }
  print('Initializing Yatogami...');
  final bot =
      NyxxFactory.createNyxxWebsocket(token, GatewayIntents.allUnprivileged)
        ..registerPlugin(Logging()) // Default logging plugin
        ..registerPlugin(
            CliIntegration()) // Cli integration for nyxx allows stopping application via SIGTERM and SIGKILl
        ..registerPlugin(
            IgnoreExceptions()) // Plugin that handles uncaught exceptions that may occur
        ..connect();

  final commands = ICommander.create(bot, prefixHandler);
  commands
    ..registerCommand("ping", _ping)
    ..registerCommand("avatar", _avatar)
    // Aliases
    ..registerCommand("av", _avatar);

  bot.onReady.first.then((_) {
    print('Yatogami is ready!');
    bot.shardManager.onConnected.first.then((_) {
      bot.shardManager.setPresence(
          PresenceBuilder.of(activity: ActivityBuilder.game("with Shido")));
    });
  });
}
