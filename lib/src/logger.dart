library a_la_carte.server.logger;

enum LoggerPriority {
  debug, info, message, warning, error, critical, fatal
}

typedef void Logger(String message, {LoggerPriority priority});

