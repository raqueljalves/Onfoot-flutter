import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  List<Map<String, dynamic>> _myReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyReports();
  }

  Future<void> _loadMyReports() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('safety_reports')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _myReports = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading reports: $e');
      setState(() => _isLoading = false);
    }
  }

  String _getReportTypeLabel(String type) {
    switch (type) {
      case 'dangerous_area':
        return 'Dangerous Area';
      case 'construction':
        return 'Construction/Obstacle';
      case 'poor_lighting':
        return 'Poor Lighting';
      default:
        return type;
    }
  }

  IconData _getReportIcon(String type) {
    switch (type) {
      case 'dangerous_area':
        return Icons.local_police;
      case 'construction':
        return Icons.construction;
      case 'poor_lighting':
        return Icons.lightbulb_outline;
      default:
        return Icons.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/home');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Safety'),
          backgroundColor: const Color(0xFF9CAF88),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/home');
            },
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _myReports.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.info_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No reports submitted yet.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _myReports.length,
                    itemBuilder: (context, index) {
                      final report = _myReports[index];
                      final type = report['type'] as String;
                      final createdAt = DateTime.parse(report['created_at']);
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: Icon(
                            _getReportIcon(type),
                            color: const Color(0xFF9CAF88),
                          ),
                          title: Text(_getReportTypeLabel(type)),
                          subtitle: Text(
                            '${createdAt.day}/${createdAt.month}/${createdAt.year} às ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteReport(report['id']),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Future<void> _deleteReport(String reportId) async {
    try {
      await Supabase.instance.client
          .from('safety_reports')
          .delete()
          .eq('id', reportId);

      setState(() {
        _myReports.removeWhere((report) => report['id'] == reportId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report apagado')),
      );
    } catch (e) {
      print('❌ Erro ao apagar report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao apagar report')),
      );
    }
  }
}