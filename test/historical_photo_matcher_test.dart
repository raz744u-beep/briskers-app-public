import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/services/historical_photo_matcher.dart';

void main() {
  const matcher = HistoricalPhotoMatcher();

  test('historical photo matcher assigns exact MobileBiz job numbers', () {
    final jobs = <Map<String, dynamic>>[
      {
        'id': 'job-6230',
        'job_number': 'MB-6230',
        'status': 'completed',
      },
      {
        'id': 'job-6087',
        'job_number': 'MB-6087',
        'status': 'completed',
      },
      {
        'id': 'job-open',
        'job_number': 'MB-7000',
        'status': 'in_progress',
      },
    ];
    final files = <Map<String, dynamic>>[
      {
        'name': 'IMG_001.jpg',
        'relative_path': 'MobileBiz/6230/IMG_001.jpg',
      },
      {
        'name': 'invoice_6087_photo_2.jpeg',
        'relative_path': 'photos/invoice_6087_photo_2.jpeg',
      },
      {
        'name': 'IMG_7000.jpg',
        'relative_path': 'MobileBiz/7000/IMG_7000.jpg',
      },
      {
        'name': 'random.jpg',
        'relative_path': 'MobileBiz/random.jpg',
      },
    ];

    final matches = matcher.exactMatches(jobs, files);

    expect(matches, hasLength(2));
    expect(
      matches.map((match) => match.job['id']).toSet(),
      {'job-6230', 'job-6087'},
    );
  });

  test('job number matching uses digit boundaries', () {
    expect(
      matcher.pathContainsJobNumber('photos/6230/a.jpg', '6230'),
      isTrue,
    );
    expect(
      matcher.pathContainsJobNumber('photos/16230/a.jpg', '6230'),
      isFalse,
    );
    expect(
      matcher.pathContainsJobNumber('photos/62301/a.jpg', '6230'),
      isFalse,
    );
  });
}
