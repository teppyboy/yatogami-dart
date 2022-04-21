import 'dart:io';
import "dart:async";
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commander/nyxx_commander.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

const defaultPrefix = "y!";

FutureOr<String?> prefixHandler(IMessage message) {
  return defaultPrefix;
}

Future<List<IUser>> getUsersFromMessage(ICommandContext context) async {
  final args = context.getArguments();
  if (args.isEmpty) {
    return Future<List<IUser>>.value([(context.author as IUser)]);
  }
  final users = List<IUser>.empty(growable: true);
  for (final arg in args) {
    var userId = int.tryParse(arg);
    userId ??= int.tryParse(arg.substring(2, arg.length - 1));
    if (userId == null) {
      continue;
    }
    try {
      users.add(await context.client.fetchUser(Snowflake(userId)));
    } catch (err) {
      print(err);
      continue;
    }
  }
  return Future<List<IUser>>.value(users);
}

Future<List<IMember>> getMembersFromMessage(ICommandContext context) async {
  final guild = context.guild;
  final members = List<IMember>.empty(growable: true);
  if (guild == null) {
    return members;
  }
  final args = context.getArguments();
  if (args.isEmpty) {
    return Future<List<IMember>>.value([context.member!]);
  }
  for (final arg in args) {
    var userId = int.tryParse(arg);
    userId ??= int.tryParse(arg.substring(2, arg.length - 1));
    if (userId == null) {
      continue;
    }
    try {
      members.add(await guild.fetchMember(Snowflake(userId)));
    } catch (err) {
      print(err);
      continue;
    }
  }
  return members;
}

void _avatar(ICommandContext context, String message) async {
  final users = await getUsersFromMessage(context);
  if (users.isEmpty) {
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description = "No user found matching your query."
          ..color = DiscordColor.red),
        mention: false,
        reply: true);
    return;
  }
  final user = users.first;
  final embed = MessageBuilder.embed(EmbedBuilder()
    ..addAuthor((author) {
      author.name = user.tag + "'s avatar";
      author.iconUrl = user.avatarURL(size: 128);
    })
    ..color = DiscordColor.magenta
    ..imageUrl = user.avatarURL(size: 4096)
    ..addFooter((footer) {
      footer.text = "UID: ${user.id}";
    }));
  context.reply(embed, reply: true, mention: false);
}

void _ping(ICommandContext context, String message) {
  context.reply(MessageBuilder.content("Pong!"), reply: true, mention: false);
}

Future<void> startServer(INyxxWebsocket bot) async {
  final port = int.parse(Platform.environment['HTTP_PORT'] ?? '8080');

  HttpServer.bind(InternetAddress.anyIPv4, port).then((server) {
    print("Server started at $port");

    server.listen((request) {
      request.response
        ..statusCode = 200
        ..write("""{
    "name": "Yatogami",
    "uptime": ${DateTime.now().millisecondsSinceEpoch - bot.startTime.millisecondsSinceEpoch},
}""") // Fake JSON response
        ..close();
    });
  });
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

  final interactions = IInteractions.create(WebsocketInteractionBackend(bot));
  final singleCommand = SlashCommandBuilder(
      "ping", "Simple command that responds with `pong`", [])
    ..registerHandler((event) async {
      // Handler accepts a function with parameter of SlashCommandInteraction which contains
      // all of the stuff needed to respond to interaction.
      // From there you have two routes: ack and then respond later or respond immediately without ack.
      // Sending ack will display indicator that bot is thinking and from there you will have 15 mins to respond to
      // that interaction.
      await event.respond(MessageBuilder.content("Pong!"));
    });
  interactions
    ..registerSlashCommand(singleCommand)
    ..syncOnReady();
  bot.onReady.first.then((_) {
    print('Setting presence...');
    bot.shardManager.onConnected.forEach((element) {
      bot.shardManager.setPresence(
          PresenceBuilder.of(activity: ActivityBuilder.game("with Shido")));
    });
    startServer(bot);
  });
}
