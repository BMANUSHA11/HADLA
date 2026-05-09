import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = true;

  try {
    await Firebase.initializeApp();
  } catch (_) {
    firebaseReady = false;
  }

  runApp(LocalHelperApp(firebaseReady: firebaseReady));
}

class LocalHelperApp extends StatelessWidget {
  const LocalHelperApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF25D6A2);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Local Helper',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          primary: seed,
          secondary: const Color(0xFFFFC857),
          surface: const Color(0xFF111820),
        ),
        scaffoldBackgroundColor: const Color(0xFF071016),
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          color: const Color(0xFF121C24),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF26333D)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF101A22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Color(0xFF82909B)),
        ),
      ),
      home: AuthGate(firebaseReady: firebaseReady),
    );
  }
}

enum UserRole { user, worker }

const bookingStatuses = ['requested', 'accepted', 'on the way', 'completed'];

String roleToValue(UserRole role) =>
    role == UserRole.worker ? 'worker' : 'user';

UserRole roleFromValue(String? value) {
  return value == 'worker' ? UserRole.worker : UserRole.user;
}

String authEmailFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return '$digits@localhelper.app';
}

String formatDateTime(DateTime dateTime) {
  final hour = dateTime.hour > 12
      ? dateTime.hour - 12
      : (dateTime.hour == 0 ? 12 : dateTime.hour);
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}, $hour:$minute $period';
}

DateTime? dateTimeFromFirestore(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

class BookingData {
  const BookingData({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  String get workerName => data['workerName'] as String? ?? 'Worker';
  String get service => data['service'] as String? ?? 'Service';
  String get area => data['area'] as String? ?? 'Area';
  String get address => data['address'] as String? ?? 'Address not added';
  String get issue => data['issue'] as String? ?? 'No issue description';
  String get status => data['status'] as String? ?? 'requested';
  String get phone => data['phone'] as String? ?? '';
  int get price => data['price'] as int? ?? 0;
  bool get reviewed => data['reviewed'] as bool? ?? false;
  DateTime? get scheduledAt => dateTimeFromFirestore(data['scheduledAt']);
}

class UserProfile {
  const UserProfile({required this.displayName, required this.role});

  final String displayName;
  final UserRole role;
}

Future<UserProfile> loadOrRepairUserProfile({
  required User user,
  UserRole fallbackRole = UserRole.user,
  String? fallbackName,
  String? phone,
}) async {
  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final userDoc = await userRef.get();
  final data = userDoc.data();

  if (userDoc.exists && data != null) {
    final role = roleFromValue(data['role'] as String?);
    final displayName =
        data['name'] as String? ?? user.displayName ?? fallbackName ?? 'User';
    return UserProfile(displayName: displayName, role: role);
  }

  final displayName = user.displayName ?? fallbackName ?? 'User';
  await userRef.set({
    'name': displayName,
    if (phone != null) 'phone': phone,
    'role': roleToValue(fallbackRole),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  return UserProfile(displayName: displayName, role: fallbackRole);
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const AuthScreen(firebaseReady: false);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen(firebaseReady: true);
        }

        return FutureBuilder<UserProfile>(
          future: loadOrRepairUserProfile(user: user),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }

            final profile = userSnapshot.data ??
                UserProfile(
                  displayName: user.displayName ?? 'Guest User',
                  role: UserRole.user,
                );

            return ShellScreen(
              role: profile.role,
              displayName: profile.displayName,
              firebaseReady: true,
            );
          },
        );
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.firebaseReady = true});

  final bool firebaseReady;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _role = UserRole.user;
  bool _isSignUp = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim().isEmpty
        ? (_role == UserRole.user ? 'Guest User' : 'Local Pro')
        : _nameController.text.trim();

    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      _showAuthError('Enter a valid phone number.');
      return;
    }

    if (password.length < 6) {
      _showAuthError('Password must be at least 6 characters.');
      return;
    }

    if (!widget.firebaseReady) {
      _showAuthError(
        'Firebase web is not configured. Opening demo mode for this run.',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ShellScreen(
            role: _role,
            displayName: name,
            firebaseReady: false,
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = FirebaseAuth.instance;
      final email = authEmailFromPhone(phone);

      if (_isSignUp) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;

        if (user != null) {
          await user.updateDisplayName(name);
          await loadOrRepairUserProfile(
            user: user,
            fallbackRole: _role,
            fallbackName: name,
            phone: phone,
          );
        }
      } else {
        final credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;

        if (user != null) {
          await loadOrRepairUserProfile(
            user: user,
            fallbackRole: _role,
            fallbackName: name,
            phone: phone,
          );
        }
      }
    } on FirebaseAuthException catch (error) {
      _showAuthError(_friendlyAuthMessage(error));
    } catch (_) {
      _showAuthError('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _friendlyAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists. Tap Sign in instead of Sign up.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Phone number or password is incorrect.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  void _showAuthError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height - 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.handyman_rounded,
                    color: Color(0xFF06110D),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Local Helper',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Find trusted electricians, plumbers, cleaners and repair experts near you.',
                  style: TextStyle(
                    color: Color(0xFFB6C1C9),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 30),
                RoleSelector(
                  role: _role,
                  onChanged: (role) => setState(() => _role = role),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AuthModeButton(
                        label: 'Sign in',
                        selected: !_isSignUp,
                        onTap: _isLoading
                            ? () {}
                            : () => setState(() => _isSignUp = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AuthModeButton(
                        label: 'Sign up',
                        selected: _isSignUp,
                        onTap: _isLoading
                            ? () {}
                            : () => setState(() => _isSignUp = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isSignUp) ...[
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      hintText: 'Full name',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone_android_rounded),
                    hintText: 'Phone number',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                    hintText: 'Password',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _submitAuth,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      _isLoading
                          ? 'Please wait'
                          : (_isSignUp ? 'Create account' : 'Continue'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const TrustStrip(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoleSelector extends StatelessWidget {
  const RoleSelector({super.key, required this.role, required this.onChanged});

  final UserRole role;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF101A22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF24313B)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RoleTile(
              icon: Icons.search_rounded,
              title: 'User',
              subtitle: 'Book help',
              selected: role == UserRole.user,
              onTap: () => onChanged(UserRole.user),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RoleTile(
              icon: Icons.engineering_rounded,
              title: 'Worker',
              subtitle: 'Get jobs',
              selected: role == UserRole.worker,
              onTap: () => onChanged(UserRole.worker),
            ),
          ),
        ],
      ),
    );
  }
}

class RoleTile extends StatelessWidget {
  const RoleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? const Color(0xFF06110D) : colors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? const Color(0xFF06110D) : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF17362C)
                          : const Color(0xFF92A1AB),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthModeButton extends StatelessWidget {
  const AuthModeButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? const Color(0xFF1A2830) : const Color(0xFF0E171E),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFF2A3741),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }
}

class TrustStrip extends StatelessWidget {
  const TrustStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.verified_user_rounded, 'Verified workers'),
      (Icons.star_rounded, 'Real reviews'),
      (Icons.near_me_rounded, 'Nearby jobs'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF0E171E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF25323B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, size: 16, color: const Color(0xFFFFC857)),
                const SizedBox(width: 6),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: Color(0xFFC3CDD4),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ShellScreen extends StatefulWidget {
  const ShellScreen({
    super.key,
    required this.role,
    required this.displayName,
    required this.firebaseReady,
  });

  final UserRole role;
  final String displayName;
  final bool firebaseReady;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = widget.role == UserRole.user
        ? [
            HomeScreen(displayName: widget.displayName),
            const BookingsScreen(),
            const SupportScreen(),
            ProfileScreen(
              role: widget.role,
              displayName: widget.displayName,
              firebaseReady: widget.firebaseReady,
            ),
          ]
        : [
            WorkerDashboard(displayName: widget.displayName),
            const WorkerJobsScreen(),
            const SupportScreen(),
            ProfileScreen(
              role: widget.role,
              displayName: widget.displayName,
              firebaseReady: widget.firebaseReady,
            ),
          ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: const Color(0xFF0D161D),
        indicatorColor: const Color(0xFF1E3C34),
        destinations: [
          NavigationDestination(
            icon: Icon(
              widget.role == UserRole.user
                  ? Icons.home_repair_service_outlined
                  : Icons.dashboard_outlined,
            ),
            selectedIcon: Icon(
              widget.role == UserRole.user
                  ? Icons.home_repair_service_rounded
                  : Icons.dashboard_rounded,
            ),
            label: widget.role == UserRole.user ? 'Find' : 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(
              widget.role == UserRole.user
                  ? Icons.event_note_outlined
                  : Icons.work_outline_rounded,
            ),
            selectedIcon: Icon(
              widget.role == UserRole.user
                  ? Icons.event_note_rounded
                  : Icons.work_rounded,
            ),
            label: widget.role == UserRole.user ? 'Bookings' : 'Jobs',
          ),
          const NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent_rounded),
            label: 'AI Help',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class Worker {
  const Worker({
    required this.name,
    required this.service,
    required this.rating,
    required this.reviews,
    required this.price,
    required this.phone,
    required this.distance,
    required this.eta,
    required this.area,
    required this.position,
    required this.languages,
    required this.emergency,
    required this.available,
  });

  final String name;
  final String service;
  final double rating;
  final int reviews;
  final int price;
  final String phone;
  final double distance;
  final String eta;
  final String area;
  final LatLng position;
  final List<String> languages;
  final bool emergency;
  final bool available;
}

const localHelperCenter = LatLng(12.9716, 77.5946);

const workers = [
  Worker(
    name: 'Ravi Kumar',
    service: 'Electrician',
    rating: 4.8,
    reviews: 128,
    price: 300,
    phone: '919876543210',
    distance: 1.2,
    eta: '12 min',
    area: 'Indiranagar',
    position: LatLng(12.9784, 77.6408),
    languages: ['Hindi', 'Kannada'],
    emergency: true,
    available: true,
  ),
  Worker(
    name: 'Suresh Patil',
    service: 'Plumber',
    rating: 4.6,
    reviews: 96,
    price: 250,
    phone: '919876543211',
    distance: 2.1,
    eta: '18 min',
    area: 'Koramangala',
    position: LatLng(12.9352, 77.6245),
    languages: ['Hindi', 'Tamil'],
    emergency: true,
    available: true,
  ),
  Worker(
    name: 'Mahesh Verma',
    service: 'Carpenter',
    rating: 4.7,
    reviews: 73,
    price: 400,
    phone: '919876543212',
    distance: 3.4,
    eta: '30 min',
    area: 'HSR Layout',
    position: LatLng(12.9116, 77.6389),
    languages: ['Hindi', 'English'],
    emergency: false,
    available: false,
  ),
  Worker(
    name: 'Asha Cleaning Co.',
    service: 'Cleaner',
    rating: 4.9,
    reviews: 154,
    price: 220,
    phone: '919876543213',
    distance: 1.8,
    eta: '20 min',
    area: 'Domlur',
    position: LatLng(12.9611, 77.6387),
    languages: ['Kannada', 'English'],
    emergency: false,
    available: true,
  ),
  Worker(
    name: 'Imran AC Care',
    service: 'AC Repair',
    rating: 4.5,
    reviews: 82,
    price: 500,
    phone: '919876543214',
    distance: 4.2,
    eta: '38 min',
    area: 'Whitefield',
    position: LatLng(12.9698, 77.7499),
    languages: ['Hindi', 'Urdu'],
    emergency: false,
    available: true,
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.displayName});

  final String displayName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchText = '';
  String _category = 'All';

  List<Worker> get _filteredWorkers {
    return workers.where((worker) {
      final matchesCategory = _category == 'All' || worker.service == _category;
      final query = _searchText.toLowerCase();
      final matchesSearch = query.isEmpty ||
          worker.name.toLowerCase().contains(query) ||
          worker.service.toLowerCase().contains(query) ||
          worker.area.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      ...{for (final worker in workers) worker.service},
    ];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Header(
                  title: 'Hi ${widget.displayName}',
                  subtitle: 'What service do you need today?',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              sliver: SliverToBoxAdapter(
                child: SearchPanel(
                  onChanged: (value) => setState(() => _searchText = value),
                  onVoiceTap: () => _showMessage(
                    'Voice search ready for Hindi, Kannada and Tamil demo flow.',
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: CategoryRail(
                  categories: categories,
                  selected: _category,
                  onSelected: (value) => setState(() => _category = value),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: EmergencyPanel(
                  onTap: () {
                    setState(() => _category = 'All');
                    _showMessage('Showing emergency workers near you.');
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
              sliver: SliverToBoxAdapter(
                child: NearbyMapPreview(
                  workers: _filteredWorkers,
                  onOpenMap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          NearbyWorkersMapScreen(workers: _filteredWorkers),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              sliver: SliverToBoxAdapter(
                child: SectionTitle(
                  title: 'Nearby workers',
                  trailing: '${_filteredWorkers.length} found',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              sliver: SliverList.separated(
                itemCount: _filteredWorkers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final worker = _filteredWorkers[index];
                  return WorkerCard(
                    worker: worker,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkerDetailScreen(worker: worker),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class Header extends StatelessWidget {
  const Header({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFF91A0AA))),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class SearchPanel extends StatelessWidget {
  const SearchPanel({
    super.key,
    required this.onChanged,
    required this.onVoiceTap,
  });

  final ValueChanged<String> onChanged;
  final VoidCallback onVoiceTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: onChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search plumber, electrician, area...',
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          width: 56,
          child: IconButton.filled(
            tooltip: 'Voice search',
            onPressed: onVoiceTap,
            icon: const Icon(Icons.mic_rounded),
          ),
        ),
      ],
    );
  }
}

class CategoryRail extends StatelessWidget {
  const CategoryRail({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return ChoiceChip(
            selected: selected == category,
            label: Text(category),
            onSelected: (_) => onSelected(category),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class EmergencyPanel extends StatelessWidget {
  const EmergencyPanel({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF281B1C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF5B3031)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.emergency_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency repair',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Electricians and plumbers available now',
                    style: TextStyle(color: Color(0xFFCFA8A8), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class NearbyMapPreview extends StatefulWidget {
  const NearbyMapPreview({
    super.key,
    required this.workers,
    required this.onOpenMap,
  });

  final List<Worker> workers;
  final VoidCallback onOpenMap;

  @override
  State<NearbyMapPreview> createState() => _NearbyMapPreviewState();
}

class _NearbyMapPreviewState extends State<NearbyMapPreview> {
  GoogleMapController? _controller;

  Set<Marker> get _markers {
    return {
      const Marker(
        markerId: MarkerId('you'),
        position: localHelperCenter,
        infoWindow: InfoWindow(title: 'Your area'),
      ),
      for (final worker in widget.workers)
        Marker(
          markerId: MarkerId(worker.phone),
          position: worker.position,
          infoWindow: InfoWindow(
            title: worker.name,
            snippet: '${worker.service} • ${worker.eta}',
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: const Color(0xFF111B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF26333D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: localHelperCenter,
                zoom: 11.8,
              ),
              markers: _markers,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              onMapCreated: (controller) => _controller = controller,
              onTap: (_) => widget.onOpenMap(),
            ),
          ),
          const Positioned(left: 12, top: 12, child: _MapLabel()),
          Positioned(
            right: 12,
            top: 12,
            child: IconButton.filled(
              tooltip: 'Open full map',
              onPressed: widget.onOpenMap,
              icon: const Icon(Icons.open_in_full_rounded),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: MapSummaryBar(
              workerCount: widget.workers.length,
              nearestWorker:
                  widget.workers.isEmpty ? null : widget.workers.first,
              onTap: widget.onOpenMap,
              onRecenter: () {
                _controller?.animateCamera(
                  CameraUpdate.newLatLngZoom(localHelperCenter, 11.8),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xDD071016),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF25D6A2)),
          SizedBox(width: 6),
          Text('Live nearby map',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class MapSummaryBar extends StatelessWidget {
  const MapSummaryBar({
    super.key,
    required this.workerCount,
    required this.nearestWorker,
    required this.onTap,
    required this.onRecenter,
  });

  final int workerCount;
  final Worker? nearestWorker;
  final VoidCallback onTap;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE071016),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Recenter map',
                onPressed: onRecenter,
                icon: const Icon(Icons.my_location_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$workerCount workers around you',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nearestWorker == null
                          ? 'Search a service to see markers'
                          : 'Nearest: ${nearestWorker!.name} • ${nearestWorker!.eta}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB8C3CB),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_up_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class NearbyWorkersMapScreen extends StatefulWidget {
  const NearbyWorkersMapScreen({super.key, required this.workers});

  final List<Worker> workers;

  @override
  State<NearbyWorkersMapScreen> createState() => _NearbyWorkersMapScreenState();
}

class _NearbyWorkersMapScreenState extends State<NearbyWorkersMapScreen> {
  GoogleMapController? _controller;
  Worker? _selectedWorker;
  LatLng _userPosition = localHelperCenter;

  @override
  void initState() {
    super.initState();
    _selectedWorker = widget.workers.isEmpty ? null : widget.workers.first;
  }

  Set<Marker> get _markers {
    return {
      Marker(
        markerId: const MarkerId('you'),
        position: _userPosition,
        infoWindow: const InfoWindow(title: 'You are here'),
      ),
      for (final worker in widget.workers)
        Marker(
          markerId: MarkerId(worker.phone),
          position: worker.position,
          infoWindow: InfoWindow(
            title: worker.name,
            snippet: '${worker.service} • ${worker.eta}',
          ),
          onTap: () {
            setState(() => _selectedWorker = worker);
          },
        ),
    };
  }

  Future<void> _useCurrentLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Location permission is required.')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    final latLng = LatLng(position.latitude, position.longitude);

    setState(() => _userPosition = latLng);
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
  }

  void _focusWorker(Worker worker) {
    setState(() => _selectedWorker = worker);
    _controller
        ?.animateCamera(CameraUpdate.newLatLngZoom(worker.position, 14.2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: localHelperCenter,
                zoom: 12.2,
              ),
              markers: _markers,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (controller) => _controller = controller,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 12,
            child: _MapTopBar(onLocationTap: _useCurrentLocation),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NearbyWorkerSheet(
              workers: widget.workers,
              selectedWorker: _selectedWorker,
              onWorkerTap: _focusWorker,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapTopBar extends StatelessWidget {
  const _MapTopBar({required this.onLocationTap});

  final VoidCallback onLocationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filled(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xEE071016),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_rounded, color: Color(0xFF25D6A2)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Workers near you',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: 'Use current location',
          onPressed: onLocationTap,
          icon: const Icon(Icons.my_location_rounded),
        ),
      ],
    );
  }
}

class NearbyWorkerSheet extends StatelessWidget {
  const NearbyWorkerSheet({
    super.key,
    required this.workers,
    required this.selectedWorker,
    required this.onWorkerTap,
  });

  final List<Worker> workers;
  final Worker? selectedWorker;
  final ValueChanged<Worker> onWorkerTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF071016),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF35444F),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SectionTitle(
              title: 'Nearby workers',
              trailing: '${workers.length} found',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 142,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: workers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final worker = workers[index];
                  final selected = selectedWorker?.phone == worker.phone;

                  return SizedBox(
                    width: 260,
                    child: WorkerMapCard(
                      worker: worker,
                      selected: selected,
                      onTap: () => onWorkerTap(worker),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkerMapCard extends StatelessWidget {
  const WorkerMapCard({
    super.key,
    required this.worker,
    required this.selected,
    required this.onTap,
  });

  final Worker worker;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? const Color(0xFF17382E) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WorkerAvatar(service: worker.service),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${worker.service} • ${worker.eta}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB4C1C9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WorkerDetailScreen(worker: worker),
                        ),
                      ),
                      icon: const Icon(Icons.event_available_rounded),
                      label: const Text('Book'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Call worker',
                    onPressed: () => launchWorkerUri('tel:${worker.phone}'),
                    icon: const Icon(Icons.call_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: Color(0xFF91A0AA))),
      ],
    );
  }
}

class WorkerCard extends StatelessWidget {
  const WorkerCard({super.key, required this.worker, required this.onTap});

  final Worker worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WorkerAvatar(service: worker.service),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${worker.service} • ${worker.area}',
                          style: const TextStyle(color: Color(0xFF93A2AD)),
                        ),
                      ],
                    ),
                  ),
                  AvailabilityBadge(available: worker.available),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Metric(
                    icon: Icons.star_rounded,
                    value: '${worker.rating}',
                    label: '${worker.reviews} reviews',
                  ),
                  Metric(
                    icon: Icons.near_me_rounded,
                    value: '${worker.distance} km',
                    label: worker.eta,
                  ),
                  Metric(
                    icon: Icons.currency_rupee_rounded,
                    value: '${worker.price}',
                    label: 'estimated',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchWorkerUri('tel:${worker.phone}'),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => launchWorkerUri(
                        'https://wa.me/${worker.phone}?text=Hi%2C%20I%20need%20help%20with%20${Uri.encodeComponent(worker.service)}',
                      ),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> launchWorkerUri(String value) async {
  final uri = Uri.parse(value);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class WorkerAvatar extends StatelessWidget {
  const WorkerAvatar({super.key, required this.service});

  final String service;

  IconData get icon {
    switch (service) {
      case 'Electrician':
        return Icons.electrical_services_rounded;
      case 'Plumber':
        return Icons.plumbing_rounded;
      case 'Carpenter':
        return Icons.carpenter_rounded;
      case 'Cleaner':
        return Icons.cleaning_services_rounded;
      default:
        return Icons.build_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1B2B32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: available ? const Color(0xFF17382E) : const Color(0xFF2C3035),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        available ? 'Open' : 'Busy',
        style: TextStyle(
          color: available ? const Color(0xFF6EF0C6) : const Color(0xFFB4BDC4),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFFFC857)),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E9CA6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkerDetailScreen extends StatelessWidget {
  const WorkerDetailScreen({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(worker.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        WorkerAvatar(service: worker.service),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                worker.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${worker.service} in ${worker.area}',
                                style: const TextStyle(
                                  color: Color(0xFF98A7B1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        InfoPill(
                          icon: Icons.star_rounded,
                          label: '${worker.rating} rating',
                        ),
                        InfoPill(
                          icon: Icons.rate_review_rounded,
                          label: '${worker.reviews} reviews',
                        ),
                        InfoPill(
                          icon: Icons.translate_rounded,
                          label: worker.languages.join(', '),
                        ),
                        InfoPill(icon: Icons.timer_rounded, label: worker.eta),
                      ],
                    ),
                    const SizedBox(height: 18),
                    PriceEstimate(worker: worker),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const SectionTitle(title: 'Recent reviews'),
            const SizedBox(height: 10),
            WorkerReviewsList(worker: worker),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: () => showReviewDialog(
                context: context,
                workerName: worker.name,
                workerPhone: worker.phone,
              ),
              icon: const Icon(Icons.rate_review_rounded),
              label: const Text('Write a review'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchWorkerUri('tel:${worker.phone}'),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        launchWorkerUri('https://wa.me/${worker.phone}'),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BookingRequestScreen(worker: worker),
                  ),
                ),
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('Request booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E171E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF26333D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class PriceEstimate extends StatelessWidget {
  const PriceEstimate({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final low = worker.price;
    final high = worker.price + 180;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101A22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_rupee_rounded, color: Color(0xFFFFC857)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estimated price',
                  style: TextStyle(color: Color(0xFF93A2AD), fontSize: 12),
                ),
                Text(
                  'Rs $low - Rs $high',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookingRequestScreen extends StatefulWidget {
  const BookingRequestScreen({super.key, required this.worker});

  final Worker worker;

  @override
  State<BookingRequestScreen> createState() => _BookingRequestScreenState();
}

class _BookingRequestScreenState extends State<BookingRequestScreen> {
  final _addressController = TextEditingController();
  final _issueController = TextEditingController();
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 2));
  bool _isSaving = false;

  @override
  void dispose() {
    _addressController.dispose();
    _issueController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) {
      return;
    }

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submitBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    final address = _addressController.text.trim();
    final issue = _issueController.text.trim();

    if (user == null) {
      _showMessage('Please sign in before booking.');
      return;
    }

    if (address.length < 8) {
      _showMessage('Add a complete address.');
      return;
    }

    if (issue.length < 6) {
      _showMessage('Describe the issue briefly.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('bookings').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Customer',
        'workerName': widget.worker.name,
        'workerPhone': widget.worker.phone,
        'phone': widget.worker.phone,
        'service': widget.worker.service,
        'price': widget.worker.price,
        'area': widget.worker.area,
        'address': address,
        'issue': issue,
        'status': 'requested',
        'reviewed': false,
        'scheduledAt': Timestamp.fromDate(_scheduledAt),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 12));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking request sent')),
        );
        Navigator.of(context).pop();
      }
    } on TimeoutException {
      _showMessage(
        'Booking is taking too long. Check internet and Firestore rules.',
      );
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? 'Could not save booking right now.');
    } catch (_) {
      _showMessage('Could not save booking right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request booking')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: ListTile(
                leading: WorkerAvatar(service: widget.worker.service),
                title: Text(
                  widget.worker.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${widget.worker.service} • Rs ${widget.worker.price}-${widget.worker.price + 180}',
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined),
                hintText: 'Full address / landmark',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _issueController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.description_outlined),
                hintText: 'Describe the issue',
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text(
                  'Preferred date and time',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(formatDateTime(_scheduledAt)),
                trailing: TextButton(
                  onPressed: _pickDate,
                  child: const Text('Change'),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _submitBooking,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isSaving ? 'Sending' : 'Send booking request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.name, required this.text});

  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.format_quote_rounded, color: Color(0xFFFFC857)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Color(0xFFB9C4CB))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkerReviewsList extends StatelessWidget {
  const WorkerReviewsList({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('workerPhone', isEqualTo: worker.phone)
          .snapshots(),
      builder: (context, snapshot) {
        final reviewDocs = snapshot.data?.docs ?? [];

        if (reviewDocs.isEmpty) {
          return const Column(
            children: [
              ReviewTile(
                name: 'Neha S.',
                text: 'Arrived fast, explained the issue clearly and fixed it.',
              ),
              SizedBox(height: 10),
              ReviewTile(
                name: 'Arjun M.',
                text: 'Good pricing and polite service. Would book again.',
              ),
            ],
          );
        }

        return Column(
          children: [
            for (final doc in reviewDocs.take(4)) ...[
              ReviewTile(
                name: doc.data()['userName'] as String? ?? 'Customer',
                text:
                    '${doc.data()['rating'] ?? 5}/5 • ${doc.data()['comment'] as String? ?? 'Good service.'}',
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

Future<void> showReviewDialog({
  required BuildContext context,
  required String workerName,
  required String workerPhone,
  String? bookingId,
}) async {
  final commentController = TextEditingController();
  var rating = 5;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var isSaving = false;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> saveReview() async {
            final user = FirebaseAuth.instance.currentUser;
            final comment = commentController.text.trim();

            if (user == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please sign in to review.')),
              );
              return;
            }

            if (comment.length < 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Write a short review first.')),
              );
              return;
            }

            setDialogState(() => isSaving = true);

            await FirebaseFirestore.instance.collection('reviews').add({
              'bookingId': bookingId,
              'workerName': workerName,
              'workerPhone': workerPhone,
              'userId': user.uid,
              'userName': user.displayName ?? 'Customer',
              'rating': rating,
              'comment': comment,
              'createdAt': FieldValue.serverTimestamp(),
            });

            if (bookingId != null) {
              await FirebaseFirestore.instance
                  .collection('bookings')
                  .doc(bookingId)
                  .update({
                'reviewed': true,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }

            if (context.mounted) {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Review submitted')),
              );
            }
          }

          return AlertDialog(
            title: Text('Review $workerName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 1; index <= 5; index++)
                      IconButton(
                        onPressed: () => setDialogState(() => rating = index),
                        icon: Icon(
                          index <= rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFFFC857),
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: commentController,
                  minLines: 3,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'How was the service?',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSaving ? null : saveReview,
                child: Text(isSaving ? 'Saving' : 'Submit'),
              ),
            ],
          );
        },
      );
    },
  );

  commentController.dispose();
}

class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: user == null
              ? null
              : FirebaseFirestore.instance
                  .collection('bookings')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
          builder: (context, snapshot) {
            final bookings = (snapshot.data?.docs ?? [])
                .map((doc) => BookingData(id: doc.id, data: doc.data()))
                .toList()
              ..sort((a, b) {
                final aDate = a.scheduledAt ?? DateTime(2000);
                final bDate = b.scheduledAt ?? DateTime(2000);
                return bDate.compareTo(aDate);
              });

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Header(
                  title: 'Bookings',
                  subtitle: 'Track every request live',
                ),
                const SizedBox(height: 18),
                if (user == null)
                  const EmptyStateCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Sign in required',
                    subtitle: 'Create an account to track bookings.',
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (bookings.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.event_busy_rounded,
                    title: 'No bookings yet',
                    subtitle: 'Book a worker and it will appear here.',
                  )
                else
                  for (final booking in bookings) ...[
                    BookingStatusCard(booking: booking),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF94A3AD))),
          ],
        ),
      ),
    );
  }
}

class BookingStatusCard extends StatelessWidget {
  const BookingStatusCard({super.key, required this.booking});

  final BookingData booking;

  double get _progress {
    final index = bookingStatuses.indexOf(booking.status);
    if (index < 0) {
      return 0.25;
    }
    return (index + 1) / bookingStatuses.length;
  }

  @override
  Widget build(BuildContext context) {
    final complete = booking.status == 'completed';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                WorkerAvatar(service: booking.service),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.workerName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${booking.service} • ${booking.area}',
                        style: const TextStyle(color: Color(0xFF94A3AD)),
                      ),
                    ],
                  ),
                ),
                StatusPill(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(
              booking.scheduledAt == null
                  ? 'Schedule not set'
                  : formatDateTime(booking.scheduledAt!),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              booking.issue,
              style: const TextStyle(color: Color(0xFFB8C3CB)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchWorkerUri('tel:${booking.phone}'),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call'),
                  ),
                ),
                if (complete && !booking.reviewed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showReviewDialog(
                        context: context,
                        bookingId: booking.id,
                        workerName: booking.workerName,
                        workerPhone: booking.phone,
                      ),
                      icon: const Icon(Icons.star_rounded),
                      label: const Text('Review'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: status == 'completed'
            ? const Color(0xFF24303A)
            : const Color(0xFF17382E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: status == 'completed'
              ? const Color(0xFFB7C1C8)
              : Theme.of(context).colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [
    const ChatMessage(
      text:
          'Hi, I am your Local Helper assistant. Ask me about workers, booking, price estimates, emergencies, login issues or reviews.',
      fromUser: false,
    ),
  ];
  bool _isTyping = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? quickMessage]) {
    final text = (quickMessage ?? _messageController.text).trim();
    if (text.isEmpty || _isTyping) {
      return;
    }

    setState(() {
      _messages.add(ChatMessage(text: text, fromUser: true));
      _isTyping = true;
    });
    _messageController.clear();
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages
            .add(ChatMessage(text: _buildSupportReply(text), fromUser: false));
        _isTyping = false;
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _buildSupportReply(String message) {
    final text = message.toLowerCase();

    if (_containsAny(text, ['emergency', 'urgent', 'now', 'immediate'])) {
      final emergencyWorkers = workers
          .where((worker) => worker.emergency && worker.available)
          .map((worker) => '${worker.name} (${worker.service}, ${worker.eta})')
          .join(', ');

      return 'For urgent help, use the Emergency repair panel on the Find tab. Available emergency workers right now: $emergencyWorkers.';
    }

    if (_containsAny(text, ['price', 'cost', 'estimate', 'charge', 'rate'])) {
      final suggestions = workers
          .map((worker) =>
              '${worker.service}: Rs ${worker.price}-${worker.price + 180}')
          .join('\n');

      return 'Here are quick estimates:\n$suggestions\nFinal price can change after inspection, distance, and parts.';
    }

    if (_containsAny(text, ['book', 'booking', 'request', 'appointment'])) {
      return 'To book: open Find, choose a worker, check rating and price, then tap Request booking. Your request is saved in Firestore with status "requested".';
    }

    if (_containsAny(text, ['worker', 'nearby', 'find', 'search'])) {
      final nearest = [...workers]
        ..sort((a, b) => a.distance.compareTo(b.distance));
      final topWorkers = nearest
          .take(3)
          .map((worker) =>
              '${worker.name} - ${worker.service}, ${worker.distance} km away')
          .join('\n');

      return 'Nearest workers:\n$topWorkers\nYou can search by service, worker name, or area on the Find tab.';
    }

    if (_containsAny(text, ['rating', 'review', 'trusted', 'verified'])) {
      return 'Worker cards show rating, review count, distance, estimated price and availability. Open a worker profile to see review examples before booking.';
    }

    if (_containsAny(text, [
      'login',
      'signin',
      'sign in',
      'signup',
      'sign up',
      'firebase',
      'internal error'
    ])) {
      return 'For login issues, first enable Email/Password in Firebase Authentication. If you are on Chrome, add Firebase web config. On Android, your google-services.json is already connected.';
    }

    if (_containsAny(text, ['call', 'whatsapp', 'contact', 'phone'])) {
      return 'Every worker card has Call and WhatsApp buttons. Call opens your dialer, and WhatsApp opens a chat if WhatsApp is installed.';
    }

    if (_containsAny(text, ['hello', 'hi', 'hey'])) {
      return 'Hi! Tell me what you need, like "find plumber", "price for electrician", "emergency help", or "booking problem".';
    }

    return 'I can help with finding workers, emergency service, price estimates, booking steps, reviews, login problems, call and WhatsApp support. Try asking "find electrician nearby" or "estimate plumber cost".';
  }

  bool _containsAny(String text, List<String> words) {
    return words.any(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Header(
                title: 'AI support',
                subtitle: 'Quick answers for bookings, workers and prices',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 42,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: [
                  SupportPromptChip(
                    label: 'Price estimate',
                    onTap: () => _sendMessage('Estimate electrician price'),
                  ),
                  SupportPromptChip(
                    label: 'Emergency',
                    onTap: () => _sendMessage('I need emergency help now'),
                  ),
                  SupportPromptChip(
                    label: 'Find workers',
                    onTap: () => _sendMessage('Find nearby workers'),
                  ),
                  SupportPromptChip(
                    label: 'Login issue',
                    onTap: () => _sendMessage('I have a Firebase login issue'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == _messages.length) {
                    return const ChatBubble(
                      text: 'Typing...',
                      fromUser: false,
                    );
                  }

                  final message = _messages[index];
                  return ChatBubble(
                    text: message.text,
                    fromUser: message.fromUser,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Ask about prices, workers or booking status',
                  suffixIcon: IconButton(
                    onPressed: _isTyping ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class SupportPromptChip extends StatelessWidget {
  const SupportPromptChip(
      {super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
        onPressed: onTap,
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.text, required this.fromUser});

  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: fromUser
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFF121C24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fromUser ? const Color(0xFF06110D) : Colors.white,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class WorkerDashboard extends StatelessWidget {
  const WorkerDashboard({super.key, required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
          builder: (context, snapshot) {
            final bookings = (snapshot.data?.docs ?? [])
                .map((doc) => BookingData(id: doc.id, data: doc.data()))
                .toList();
            final active = bookings
                .where((booking) =>
                    booking.status != 'completed' &&
                    booking.status != 'rejected')
                .toList();
            final completed = bookings
                .where((booking) => booking.status == 'completed')
                .toList();
            final earnings = completed.fold<int>(
              0,
              (total, booking) => total + booking.price,
            );

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Header(
                  title: 'Hi $displayName',
                  subtitle: 'Your worker dashboard is ready',
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: WorkerStatCard(
                        value: '${active.length}',
                        label: 'Active jobs',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WorkerStatCard(
                        value: '${completed.length}',
                        label: 'Completed',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: WorkerStatCard(
                        value: 'Rs $earnings',
                        label: 'Earnings',
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: WorkerStatCard(value: '4.8', label: 'Rating'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionTitle(title: 'New requests'),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (active.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.work_off_rounded,
                    title: 'No active jobs',
                    subtitle: 'New customer requests will appear here.',
                  )
                else
                  for (final booking in active.take(3)) ...[
                    JobRequestCard(booking: booking),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class WorkerStatCard extends StatelessWidget {
  const WorkerStatCard({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Color(0xFF94A3AD))),
          ],
        ),
      ),
    );
  }
}

class WorkerJobsScreen extends StatelessWidget {
  const WorkerJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
          builder: (context, snapshot) {
            final bookings = (snapshot.data?.docs ?? [])
                .map((doc) => BookingData(id: doc.id, data: doc.data()))
                .toList()
              ..sort((a, b) {
                final aDate = a.scheduledAt ?? DateTime(2000);
                final bDate = b.scheduledAt ?? DateTime(2000);
                return bDate.compareTo(aDate);
              });

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Header(
                  title: 'Jobs',
                  subtitle: 'Accept requests and update live status',
                ),
                const SizedBox(height: 18),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (bookings.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.work_off_rounded,
                    title: 'No jobs yet',
                    subtitle: 'Customer bookings will appear here.',
                  )
                else
                  for (final booking in bookings) ...[
                    JobRequestCard(booking: booking),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class JobRequestCard extends StatelessWidget {
  const JobRequestCard({super.key, required this.booking});

  final BookingData booking;

  String? get nextStatus {
    switch (booking.status) {
      case 'requested':
        return 'accepted';
      case 'accepted':
        return 'on the way';
      case 'on the way':
        return 'completed';
      default:
        return null;
    }
  }

  Future<void> _updateStatus(BuildContext context, String status) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(booking.id)
        .update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking marked $status')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = nextStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.work_history_rounded,
                  color: Color(0xFFFFC857),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.issue,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${booking.service} • ${booking.area} • Rs ${booking.price}-${booking.price + 180}',
                        style: const TextStyle(color: Color(0xFF94A3AD)),
                      ),
                    ],
                  ),
                ),
                StatusPill(status: booking.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              booking.address,
              style: const TextStyle(color: Color(0xFFB8C3CB)),
            ),
            if (booking.scheduledAt != null) ...[
              const SizedBox(height: 8),
              Text(
                formatDateTime(booking.scheduledAt!),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchWorkerUri('tel:${booking.phone}'),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: status == null
                        ? null
                        : () => _updateStatus(context, status),
                    child: Text(
                      status == 'accepted'
                          ? 'Accept'
                          : status == 'on the way'
                              ? 'On way'
                              : status == 'completed'
                                  ? 'Complete'
                                  : 'Done',
                    ),
                  ),
                ),
              ],
            ),
            if (booking.status == 'requested') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _updateStatus(context, 'rejected'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LegacyJobRequestCard extends StatelessWidget {
  const LegacyJobRequestCard({
    super.key,
    required this.title,
    required this.area,
    required this.price,
  });

  final String title;
  final String area;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.work_history_rounded, color: Color(0xFFFFC857)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$area • $price',
                    style: const TextStyle(color: Color(0xFF94A3AD)),
                  ),
                ],
              ),
            ),
            FilledButton(onPressed: () {}, child: const Text('Accept')),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.role,
    required this.displayName,
    required this.firebaseReady,
  });

  final UserRole role;
  final String displayName;
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: user == null || !firebaseReady
              ? null
              : FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? {};
            final name = data['name'] as String? ?? displayName;
            final address =
                data['address'] as String? ?? 'Bengaluru, Karnataka';
            final skills = data['skills'] as String? ?? 'Electrician, Plumber';
            final serviceArea =
                data['serviceArea'] as String? ?? 'Bengaluru local areas';
            final experience = data['experience'] as String? ?? '2 years';
            final price = data['price'] as String? ?? '300';

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Header(
                  title: name,
                  subtitle: role == UserRole.user
                      ? 'Customer account'
                      : 'Worker account',
                ),
                const SizedBox(height: 18),
                Card(
                  child: Column(
                    children: [
                      ProfileRow(
                        icon: Icons.verified_user_rounded,
                        title: role == UserRole.user
                            ? 'Verified phone'
                            : 'KYC verification',
                        subtitle: 'Ready for booking requests',
                      ),
                      const Divider(height: 1),
                      ProfileRow(
                        icon: Icons.location_on_rounded,
                        title: role == UserRole.user
                            ? 'Saved address'
                            : 'Service location',
                        subtitle: role == UserRole.user ? address : serviceArea,
                      ),
                      const Divider(height: 1),
                      ProfileRow(
                        icon: role == UserRole.user
                            ? Icons.language_rounded
                            : Icons.handyman_rounded,
                        title: role == UserRole.user ? 'Languages' : 'Skills',
                        subtitle: role == UserRole.user
                            ? 'English, Hindi, Kannada'
                            : skills,
                      ),
                      if (role == UserRole.worker) ...[
                        const Divider(height: 1),
                        ProfileRow(
                          icon: Icons.workspace_premium_rounded,
                          title: 'Experience',
                          subtitle: experience,
                        ),
                        const Divider(height: 1),
                        ProfileRow(
                          icon: Icons.currency_rupee_rounded,
                          title: 'Base price',
                          subtitle: 'Rs $price',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: user == null || !firebaseReady
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(
                                role: role,
                                initialData: data,
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit profile'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: user == null || !firebaseReady
                      ? null
                      : () async {
                          final newRole = role == UserRole.user
                              ? UserRole.worker
                              : UserRole.user;
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .set({
                            'role': roleToValue(newRole),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          if (context.mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => ShellScreen(
                                  role: newRole,
                                  displayName: name,
                                  firebaseReady: firebaseReady,
                                ),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    role == UserRole.user
                        ? 'Switch to worker account'
                        : 'Switch to customer account',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    if (firebaseReady) {
                      FirebaseAuth.instance.signOut();
                      return;
                    }

                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const AuthScreen(firebaseReady: false),
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.role,
    required this.initialData,
  });

  final UserRole role;
  final Map<String, dynamic> initialData;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _skillsController;
  late final TextEditingController _experienceController;
  late final TextEditingController _serviceAreaController;
  late final TextEditingController _priceController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialData['name'] as String? ?? '',
    );
    _addressController = TextEditingController(
      text: widget.initialData['address'] as String? ?? '',
    );
    _skillsController = TextEditingController(
      text: widget.initialData['skills'] as String? ?? '',
    );
    _experienceController = TextEditingController(
      text: widget.initialData['experience'] as String? ?? '',
    );
    _serviceAreaController = TextEditingController(
      text: widget.initialData['serviceArea'] as String? ?? '',
    );
    _priceController = TextEditingController(
      text: widget.initialData['price'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _skillsController.dispose();
    _experienceController.dispose();
    _serviceAreaController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() => _isSaving = true);

    final updates = <String, dynamic>{
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (widget.role == UserRole.worker) {
      updates.addAll({
        'skills': _skillsController.text.trim(),
        'experience': _experienceController.text.trim(),
        'serviceArea': _serviceAreaController.text.trim(),
        'price': _priceController.text.trim(),
      });
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(updates, SetOptions(merge: true));
    await user.updateDisplayName(_nameController.text.trim());

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline_rounded),
                hintText: 'Full name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined),
                hintText: 'Address',
              ),
            ),
            if (widget.role == UserRole.worker) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _skillsController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.handyman_outlined),
                  hintText: 'Skills, e.g. Electrician, AC repair',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _experienceController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                  hintText: 'Experience, e.g. 3 years',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _serviceAreaController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.map_outlined),
                  hintText: 'Service area',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                  hintText: 'Base price',
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: const Icon(Icons.save_rounded),
                label: Text(_isSaving ? 'Saving' : 'Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
    );
  }
}
