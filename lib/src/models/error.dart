class UploadError {
  final String message;
  final StackTrace? stackTrace;

  UploadError(this.message, [this.stackTrace]);

  @override
  String toString() {
    return 'Message: $message Stack Trace: $stackTrace';
  }
}
