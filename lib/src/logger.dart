library a_la_carte.server.logger;

import 'dart:io';

enum LoggerPriority { debug, info, message, warning, error, critical, fatal }

typedef void Logger(String message, {LoggerPriority priority});

void defaultLogger(String message,
    {LoggerPriority priority: LoggerPriority.info}) {
  stderr.writeln('[$priority] $message');
}
