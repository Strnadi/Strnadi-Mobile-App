Map<String, dynamic> itemJson(int id) => {
      'recordingId': id,
      'representativePartId': null,
      'locationPartId': id + 100,
      'locationSource': 'latestPart',
      'name': 'Recording $id',
      'createdAt': '2026-09-08T07:30:00Z',
      'position': {'latitude': 50.0, 'longitude': 14.0},
      'source': 'unknown',
    };
Map<String, dynamic> dialectJson(
        {int id = 1,
        String code = 'unknown',
        String color = '#445566',
        int count = 1,
        double percentage = 100}) =>
    {
      'id': id,
      'dialectCode': code,
      'color': color,
      'hintOrder': 0,
      'isDialect': false,
      'contributionCount': count,
      'percentage': percentage,
    };
Map<String, dynamic> clusterJson() => {
      'kind': 'cluster',
      'id': 'cluster/a',
      'latitude': 50.0,
      'longitude': 14.0,
      'bounds': {'north': 50.0, 'south': 50.0, 'east': 14.0, 'west': 14.0},
      'count': 6,
      'source': 'mixed',
      'dialects': [
        dialectJson(
            id: 1, code: 'A', color: '#FF0000', count: 4, percentage: 50),
        dialectJson(
            id: 2, code: 'B', color: '#00FF00', count: 3, percentage: 37.5),
        dialectJson(id: 3, count: 1, percentage: 12.5),
      ],
      'items': List.generate(5, (i) => itemJson(i + 1)),
      'hasMoreItems': true,
      'nextItemsCursor': 'cursor+/?=',
    };
Map<String, dynamic> recordingJson() => {
      ...itemJson(20),
      'kind': 'recording',
      'latitude': 50.0,
      'longitude': 14.0,
      'dialects': [dialectJson()],
    }..remove('position');
Map<String, dynamic> responseJson() => {
      'bounds': {'north': 51.0, 'south': 49.0, 'east': 15.0, 'west': 13.0},
      'clustered': true,
      'clusterDistanceMeters': 100.0,
      'visibleRecordingCount': 7,
      'features': [recordingJson(), clusterJson()],
    };
Map<String, dynamic> pageJson() => {
      'clusterId': 'cluster/a',
      'count': 6,
      'items': [itemJson(6)],
      'hasMoreItems': false,
      'nextItemsCursor': null,
    };
