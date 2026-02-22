import 'dart:io';

void main() async {
  final plants = [
    {
      "name": "Calamansi",
      "url":
          "https://images.unsplash.com/photo-1590005354167-8ab07d79b69b?auto=format&fit=crop&w=400&q=80",
      "file": "calamansi.jpg"
    },
    {
      "name": "Siling Labuyo",
      "url":
          "https://images.unsplash.com/photo-1596547141384-0a37af4b1ab5?auto=format&fit=crop&w=400&q=80",
      "file": "siling_labuyo.jpg"
    },
    {
      "name": "Kamatis",
      "url":
          "https://images.unsplash.com/photo-1592841200221-a6898f307baa?auto=format&fit=crop&w=400&q=80",
      "file": "kamatis.jpg"
    },
    {
      "name": "Pechay",
      "url":
          "https://images.unsplash.com/photo-1628131372551-78923053dff3?auto=format&fit=crop&w=400&q=80",
      "file": "pechay.jpg"
    },
    {
      "name": "Talong",
      "url":
          "https://images.unsplash.com/photo-1601646875865-c7e6c986c4e0?auto=format&fit=crop&w=400&q=80",
      "file": "talong.jpg"
    },
    {
      "name": "Ampalaya",
      "url":
          "https://images.unsplash.com/photo-1595856417757-19448135bdbe?auto=format&fit=crop&w=400&q=80",
      "file": "ampalaya.jpg"
    },
    {
      "name": "Okra",
      "url":
          "https://images.unsplash.com/photo-1558235287-ba8eb5e1e07b?auto=format&fit=crop&w=400&q=80",
      "file": "okra.jpg"
    },
    {
      "name": "Basil",
      "url":
          "https://images.unsplash.com/photo-1615485459318-7b9dd4b8408a?auto=format&fit=crop&w=400&q=80",
      "file": "basil.jpg"
    },
    {
      "name": "Aloe Vera",
      "url":
          "https://images.unsplash.com/photo-1596547609652-9cb5d8d76921?auto=format&fit=crop&w=400&q=80",
      "file": "aloe_vera.jpg"
    },
    {
      "name": "Snake Plant",
      "url":
          "https://images.unsplash.com/photo-1595058763073-1f1969ce7d63?auto=format&fit=crop&w=400&q=80",
      "file": "snake_plant.jpg"
    },
    {
      "name": "Gumamela",
      "url":
          "https://images.unsplash.com/photo-1587829281729-1c9f2b874fb3?auto=format&fit=crop&w=400&q=80",
      "file": "gumamela.jpg"
    },
    {
      "name": "Bougainvillea",
      "url":
          "https://images.unsplash.com/photo-1647493526367-9fd5035fcecd?auto=format&fit=crop&w=400&q=80",
      "file": "bougainvillea.jpg"
    },
    {
      "name": "Mango (Seed)",
      "url":
          "https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?auto=format&fit=crop&w=400&q=80",
      "file": "mango.jpg"
    },
    {
      "name": "Papaya",
      "url":
          "https://images.unsplash.com/photo-1589133857861-f3b177d40dd1?auto=format&fit=crop&w=400&q=80",
      "file": "papaya.jpg"
    },
    {
      "name": "Oregano",
      "url":
          "https://images.unsplash.com/photo-1600100412613-3ac5e64883d6?auto=format&fit=crop&w=400&q=80",
      "file": "oregano.jpg"
    },
    {
      "name": "Lemongrass",
      "url":
          "https://images.unsplash.com/photo-1587411768407-ed21c2ac37d2?auto=format&fit=crop&w=400&q=80",
      "file": "lemongrass.jpg"
    },
    {
      "name": "String Beans",
      "url":
          "https://images.unsplash.com/photo-1590489240409-51a4c84a0c8b?auto=format&fit=crop&w=400&q=80",
      "file": "string_beans.jpg"
    },
    {
      "name": "Mung Bean",
      "url":
          "https://images.unsplash.com/photo-1550989460-0adf9ea622e2?auto=format&fit=crop&w=400&q=80",
      "file": "mung_bean.jpg"
    },
    {
      "name": "Kang-Kong",
      "url":
          "https://images.unsplash.com/photo-1592839712760-b6f70921cb17?auto=format&fit=crop&w=400&q=80",
      "file": "kang_kong.jpg"
    },
    {
      "name": "Sibuyas",
      "url":
          "https://images.unsplash.com/photo-1587049352847-81a56d773c1c?auto=format&fit=crop&w=400&q=80",
      "file": "sibuyas.jpg"
    },
  ];

  final dir = Directory('assets/images/plants');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  var client = HttpClient();

  for (var plant in plants) {
    print("Downloading ${plant['name']}...");
    try {
      var request = await client.getUrl(Uri.parse(plant['url']!));
      var response = await request.close();
      var file = File("${dir.path}/${plant['file']}");
      await response.pipe(file.openWrite());
      print("Saved ${plant['file']}");
    } catch (e) {
      print("Failed to download ${plant['name']}: $e");
    }
  }

  client.close();
  print('Done!');
}
