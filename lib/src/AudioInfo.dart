class AudioInfo {
  String url;
  String title;
  String desc;
  String coverUrl;

  AudioInfo(this.url, {this.title, this.desc, this.coverUrl});

  AudioInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        title = json['title'],
        desc = json['desc'],
        coverUrl = json['coverUrl'];

  Map<String, String> toJson() => {
        'url': url,
        'title': title,
        'desc': desc,
        'coverUrl': coverUrl,
      };

  @override
  String toString() {
    return 'AudioInfo{url: $url, title: $title, desc: $desc, coverUrl: $coverUrl}';
  }
}
