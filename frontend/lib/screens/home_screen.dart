import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategory = 0;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _categoryButton(String title, int index) {
    final bool selected = _selectedCategory == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF702078)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF702078)
                : const Color(0xFFE5E0E5),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: selected
                ? Colors.white
                : const Color(0xFF555555),
            fontWeight:
                selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _churchCard({
    required String name,
    required String imageUrl,
    required String distance,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Church image - tappable
          GestureDetector(
            onTap: () {
              _showMessage('$name selected');
            },
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 145,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFFE8DCE9),
                        child: const Center(
                          child: Icon(
                            Icons.church,
                            size: 50,
                            color: Color(0xFF702078),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Distance
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3A43),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      distance,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ),

                // Mass button
                Positioned(
                  right: 10,
                  top: 10,
                  child: GestureDetector(
                    onTap: () {
                      _showMessage('$name timings');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'View Mass',
                        style: TextStyle(
                          color: Color(0xFF702078),
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Church name + favorite button
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Times New Roman',
                          fontSize: 17,
                          color: Color(0xFF702078),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // Favorite button
                    IconButton(
                      onPressed: () {
                        _showMessage(
                          '$name added to favorites',
                        );
                      },
                      icon: const Icon(
                        Icons.favorite_border,
                        size: 20,
                      ),
                      color: const Color(0xFF777777),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 2),

                const Text(
                  'Community church',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF999999),
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 13,
                      color: Color(0xFF702078),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // View church button
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () {
                      _showMessage(
                        'Opening $name',
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF3F1D4E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      'View church   →',
                      style: TextStyle(
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F7),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // TOP BAR
              // ------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  14,
                  10,
                ),
                child: Row(
                  children: [
                    // Logo
                    Image.asset(
                      'assets/images/logo.png',
                      width: 32,
                      height: 32,
                    ),

                    const SizedBox(width: 8),

                    const Text(
                      'FaithCircle',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF292329),
                      ),
                    ),

                    const Spacer(),

                    // Notification button
                    IconButton(
                      onPressed: () {
                        _showMessage(
                          'No new notifications',
                        );
                      },
                      icon: const Icon(
                        Icons.notifications_none,
                      ),
                      color: const Color(0xFF555555),
                    ),
                  ],
                ),
              ),

              // ------------------------------------------------
              // WELCOME / LOCATION SECTION
              // ------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF4C1768),
                        Color(0xFFB934A7),
                      ],
                    ),
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -25,
                        top: -30,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white
                                .withValues(alpha: 0.08),
                          ),
                        ),
                      ),

                      Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WELCOME, ROHIT',
                            style: TextStyle(
                              color: Color(0xFFDDB9E1),
                              fontSize: 8,
                              letterSpacing: 1,
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Find a church that\nfeels like home.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.05,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Connect with churches near you, join a service, and grow with a community.',
                            style: TextStyle(
                              color: Color(0xFFE7CFE9),
                              fontSize: 9,
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Location button
                          GestureDetector(
                            onTap: () {
                              _showMessage(
                                'Location selected',
                              );
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.16),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration:
                                        BoxDecoration(
                                      color: Colors.white
                                          .withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius:
                                          BorderRadius
                                              .circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                                  ),

                                  const SizedBox(width: 9),

                                  const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'YOUR LOCATION',
                                        style: TextStyle(
                                          color:
                                              Color(0xFFDDB9E1),
                                          fontSize: 7,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Nedumangad, Kerala',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight:
                                              FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const Spacer(),

                                  const Icon(
                                    Icons.near_me,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------
              // CHURCHES FOR YOU
              // ------------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NEARBY',
                      style: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 8,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Row(
                      children: [
                        const Text(
                          'Churches for you',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF292329),
                          ),
                        ),

                        const Spacer(),

                        TextButton(
                          onPressed: () {
                            _showMessage(
                              'Showing all churches',
                            );
                          },
                          child: const Text(
                            'View map',
                            style: TextStyle(
                              color: Color(0xFF702078),
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Search
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                      child: const TextField(
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.search,
                            size: 17,
                            color: Color(0xFF999999),
                          ),
                          hintText:
                              'Search churches or denomination',
                          hintStyle: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFAAAAAA),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Category buttons
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _categoryButton(
                            'Nearby',
                            0,
                          ),
                          const SizedBox(width: 6),
                          _categoryButton(
                            'Catholic',
                            1,
                          ),
                          const SizedBox(width: 6),
                          _categoryButton(
                            'Family friendly',
                            2,
                          ),
                          const SizedBox(width: 6),
                          _categoryButton(
                            'Youth',
                            3,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ------------------------------------------------
                    // CHURCH 1
                    // ------------------------------------------------
                    _churchCard(
                      name: 'St. Francis Church',
                      imageUrl:
                          'https://images.unsplash.com/photo-1438032005730-c779502df39b?auto=format&fit=crop&w=900&q=80',
                      distance: '0.8 km',
                      time: 'Sunday · 8:30 AM',
                    ),

                    // ------------------------------------------------
                    // CHURCH 2
                    // ------------------------------------------------
                    _churchCard(
                      name: "St. Mary's Church",
                      imageUrl:
                          'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=900&q=80',
                      distance: '1.4 km',
                      time: 'Sunday · 10:00 AM',
                    ),

                    // ------------------------------------------------
                    // BOTTOM PROMOTION
                    // ------------------------------------------------
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7E7F5),
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'NEW TO THE COMMUNITY?',
                                  style: TextStyle(
                                    color:
                                        Color(0xFF9C6B9A),
                                    fontSize: 7,
                                    letterSpacing: 1,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                const Text(
                                  "There's a place for you here.",
                                  style: TextStyle(
                                    color:
                                        Color(0xFF522054),
                                    fontSize: 15,
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                const Text(
                                  'Discover a church community that feels right for you.',
                                  style: TextStyle(
                                    color:
                                        Color(0xFF8D6B8B),
                                    fontSize: 8,
                                  ),
                                ),

                                const SizedBox(height: 10),

                                ElevatedButton(
                                  onPressed: () {
                                    _showMessage(
                                      'Finding churches for you',
                                    );
                                  },
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(
                                      0xFF702078,
                                    ),
                                    foregroundColor:
                                        Colors.white,
                                    elevation: 0,
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape:
                                        RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(7),
                                    ),
                                  ),
                                  child: const Text(
                                    'Get started  →',
                                    style: TextStyle(
                                      fontSize: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 10),

                          const Icon(
                            Icons.diversity_1,
                            size: 65,
                            color: Color(0xFFDDB5DC),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}