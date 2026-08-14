class AudioInfo {
  String url;
  String title;
  String desc;
  String coverUrl;
  int titleMaxLines;
  bool showPreviousButton;
  bool showNextButton;
  bool showStopButton;

  AudioInfo(this.url,
      {required this.title,
      required this.desc,
      required this.coverUrl,
      this.titleMaxLines = 1,
      this.showPreviousButton = false,
      this.showNextButton = true,
      this.showStopButton = true});

  AudioInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        title = json['title'],
        desc = json['desc'],
        coverUrl = json['coverUrl'],
        titleMaxLines =
            int.tryParse(json['titleMaxLines']?.toString() ?? '') ?? 1,
        showPreviousButton = json['showPreviousButton'] == true ||
            json['showPreviousButton'] == 'true',
        showNextButton =
            json['showNextButton'] == true || json['showNextButton'] == 'true',
        showStopButton =
            json['showStopButton'] == true || json['showStopButton'] == 'true';

  Map<String, String> toJson() => {
        'url': url,
        'title': title,
        'desc': desc,
        'coverUrl': coverUrl,
        'titleMaxLines': '$titleMaxLines',
        'showPreviousButton': '$showPreviousButton',
        'showNextButton': '$showNextButton',
        'showStopButton': '$showStopButton',
      };

  @override
  String toString() {
    return 'AudioInfo{url: $url, title: $title, desc: $desc, coverUrl: $coverUrl, titleMaxLines: $titleMaxLines}';
  }
}
