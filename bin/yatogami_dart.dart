import 'dart:io';
import "dart:async";
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commander/nyxx_commander.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';
import 'package:http/http.dart' as http;

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

Future<IRole?> getHighestRole(
    Iterable<Cacheable<Snowflake, IRole>> roles) async {
  IRole? highestRole;
  for (final role in roles) {
    highestRole ??= await role.getOrDownload();
    if (highestRole.position < (await role.getOrDownload()).position) {
      highestRole = await role.getOrDownload();
    }
  }
  return highestRole;
}

Future<String> getAvatar(IUser user, {int size = 4096}) async {
  var nitro = user.nitroType;
  // Prevent having to send additional request to Discord.
  if (nitro == null || nitro == NitroType.none) {
    return user.avatarURL(size: size);
  }
  var avatar = user.avatarURL(format: "gif", size: size);
  if ((await http.get(Uri.parse(avatar))).statusCode != 200) {
    avatar = user.avatarURL(size: size);
  }
  return avatar;
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

void _clear(ICommandContext context, String message) async {
  final guild = context.guild;
  final member = context.member;
  if (guild == null || member == null) {
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description = "This command does not work in DMs/Groups."
          ..color = DiscordColor.red),
        reply: true);
    return;
  }
  final senderRole = await getHighestRole(member.roles);
  if (senderRole == null || !senderRole.permissions.manageMessages) {
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description = "You don't have permission to delete messages."
          ..color = DiscordColor.red),
        reply: true);
    return;
  }
  final args = context.getArguments();
  if (args.isEmpty || args.length > 1) {
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description = "Please specify how much messages to delete."
          ..color = DiscordColor.red),
        reply: true);
    return;
  }
  final amount = int.tryParse(args.first);
  if (amount == null || amount < 1) {
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description =
              "The amount of messages to delete must be a positive number."
          ..color = DiscordColor.red),
        reply: true);
    return;
  }
  final messages = context.channel
      .downloadMessages(limit: amount, before: context.message.id);
  try {
    context.channel.bulkRemoveMessages(await messages.toList());
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Success"
          ..description = "Deleted ${messages.length} messages."
          ..color = DiscordColor.green),
        reply: true);
  } catch (e) {
    print(e);
    context.reply(
        MessageBuilder.embed(EmbedBuilder()
          ..title = "Error"
          ..description = "Failed to delete ${messages.length} messages."
          ..color = DiscordColor.red),
        reply: true);
  }
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
    ..addAuthor((author) async {
      author.name = user.tag + "'s avatar";
      author.iconUrl = await getAvatar(user, size: 128);
    })
    ..color = DiscordColor.magenta
    ..imageUrl = await getAvatar(user, size: 4096)
    ..addFooter((footer) {
      footer.text = "UID: ${user.id}";
    }));
  context.reply(embed, reply: true, mention: false);
}

void _ping(ICommandContext context, String message) {
  context.reply(
      MessageBuilder.embed(EmbedBuilder()
        ..title = "Pong!"
        ..description =
            "[Markdown test](https://www.youtube.com/watch?v=dQw4w9WgXcQ)"),
      reply: true,
      mention: false);
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
    ..registerCommand("clear", _clear)
    // Aliases
    ..registerCommand("av", _avatar);

  final interactions = IInteractions.create(WebsocketInteractionBackend(bot));
  final singleCommand = SlashCommandBuilder(
      "ping", "Simple command that responds with `pong`", [])
    ..registerHandler((event) async {
      await event.acknowledge();
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
