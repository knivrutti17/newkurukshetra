import '../models/trainer.dart';
import '../repositories/batch_repository.dart';
import '../repositories/trainer_repository.dart';

class TrainerSeedResult {
  const TrainerSeedResult({
    required this.trainersCreated,
    required this.trainersSkipped,
    required this.alreadyHadData,
  });

  final int trainersCreated;
  final int trainersSkipped;
  final bool alreadyHadData;
}

/// Populates sample trainers with deterministic IDs when triggered by an Owner.
///
/// Safe to run repeatedly: never overwrites existing records and reports what was skipped.
class TrainerSeedService {
  TrainerSeedService({
    TrainerSeedRepository? trainerRepository,
    BatchRepository? batchRepository,
  })  : _trainerRepository =
            trainerRepository ?? FirestoreTrainerRepository(),
        _batchRepository =
            batchRepository ?? FirestoreBatchRepository();

  final TrainerSeedRepository _trainerRepository;
  final BatchRepository _batchRepository;

  Future<TrainerSeedResult> loadSampleData() async {
    final sampleTrainers = _sampleTrainers;

    final trainersEmpty =
        await _trainerRepository.isTrainersCollectionEmpty();

    if (!trainersEmpty) {
      final existingCount =
          await _trainerRepository.countExistingSampleTrainers(sampleTrainers);
      if (existingCount == sampleTrainers.length) {
        return TrainerSeedResult(
          trainersCreated: 0,
          trainersSkipped: sampleTrainers.length,
          alreadyHadData: true,
        );
      }
    }

    final existingCount =
        await _trainerRepository.countExistingSampleTrainers(sampleTrainers);
    await _trainerRepository.createMissingSampleTrainers(sampleTrainers);

    // Optionally link sample batches to realistic trainers if the batches exist
    await _linkBatchesToSampleTrainers();

    return TrainerSeedResult(
      trainersCreated: sampleTrainers.length - existingCount,
      trainersSkipped: existingCount,
      alreadyHadData: false,
    );
  }

  Future<void> _linkBatchesToSampleTrainers() async {
    try {
      final batches = await _batchRepository.getBatches(
        scope: const BatchAccessScope(instituteId: 'demo-institute'),
      );
      if (batches.isEmpty) return;

      // Assign specific sample trainers to enrich the demo experience
      final batchAssignments = <String, ({String trainerId, String trainerName})>{
        'ux-apr-2026-c': (
          trainerId: 'trainer-pooja-verma',
          trainerName: 'Pooja Verma',
        ),
        'da-may-2026-b': (
          trainerId: 'trainer-aditya-sen',
          trainerName: 'Aditya Sen',
        ),
        'dm-mar-2026-a': (
          trainerId: 'trainer-ananya-joshi',
          trainerName: 'Ananya Joshi',
        ),
      };

      for (final b in batches) {
        final target = batchAssignments[b.id];
        if (target != null && b.trainerId != target.trainerId) {
          await _batchRepository.updateBatch(
            b.copyWith(
              trainerId: target.trainerId,
              trainerName: target.trainerName,
            ),
          );
        }
      }
    } catch (_) {
      // Non-fatal if batch assignment sync fails during seed
    }
  }

  List<Trainer> get _sampleTrainers => <Trainer>[
        _trainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
          phone: '+91 98201 12345',
          expertise: const [
            'Full Stack Development',
            'Flutter',
            'Dart',
            'Node.js',
            'Firebase',
          ],
          qualifications:
              'M.Tech in Software Systems, B.E. Computer Engineering',
          experienceYears: 8,
          availability: const TrainerAvailability(
            weekdays: [
              'Monday',
              'Tuesday',
              'Wednesday',
              'Thursday',
              'Friday',
            ],
            preferredTimeRange: 'Morning (09:00 AM - 01:30 PM)',
            unavailableNotes: 'Unavailable Sunday afternoons',
            generalNotes:
                'Lead instructor for full stack and mobile application cohorts.',
          ),
          createdAt: DateTime(2026, 1, 1),
        ),
        _trainer(
          id: 'trainer-pooja-verma',
          fullName: 'Pooja Verma',
          email: 'pooja.verma@demo.com',
          phone: '+91 98202 23456',
          expertise: const [
            'UI/UX Design',
            'Figma',
            'User Research',
            'Design Systems',
            'Prototyping',
          ],
          qualifications:
              'Master of Design (Interaction Design), National Institute of Design',
          experienceYears: 6,
          availability: const TrainerAvailability(
            weekdays: [
              'Tuesday',
              'Thursday',
              'Saturday',
            ],
            preferredTimeRange: 'Evening (05:00 PM - 08:30 PM)',
            unavailableNotes: 'Unavailable weekday mornings',
            generalNotes:
                'Mentors UI/UX design cohorts and conducts design review critiques.',
          ),
          createdAt: DateTime(2026, 1, 2),
        ),
        _trainer(
          id: 'trainer-aditya-sen',
          fullName: 'Aditya Sen',
          email: 'aditya.sen@demo.com',
          phone: '+91 98203 34567',
          expertise: const [
            'Data Analytics',
            'Python',
            'SQL',
            'Power BI',
            'Statistical Modeling',
          ],
          qualifications:
              'M.Sc in Applied Statistics, Certified Data Science Professional',
          experienceYears: 5,
          availability: const TrainerAvailability(
            weekdays: [
              'Monday',
              'Wednesday',
              'Friday',
              'Saturday',
            ],
            preferredTimeRange: 'Afternoon (02:00 PM - 05:00 PM)',
            unavailableNotes: 'Unavailable Monday mornings',
            generalNotes:
                'Guides data wrangling, analytics capstone projects, and BI dashboards.',
          ),
          createdAt: DateTime(2026, 1, 3),
        ),
        _trainer(
          id: 'trainer-ananya-joshi',
          fullName: 'Ananya Joshi',
          email: 'ananya.joshi@demo.com',
          phone: '+91 98204 45678',
          expertise: const [
            'Digital Marketing',
            'SEO & SEM',
            'Social Media Growth',
            'Content Marketing',
            'Google Ads',
          ],
          qualifications:
              'MBA in Marketing, Certified Digital Marketing Specialist',
          experienceYears: 7,
          availability: const TrainerAvailability(
            weekdays: [
              'Saturday',
              'Sunday',
            ],
            preferredTimeRange: 'Weekend (10:00 AM - 01:00 PM)',
            unavailableNotes:
                'Unavailable weekdays due to agency leadership commitments',
            generalNotes:
                'Specializes in weekend performance marketing masterclasses.',
          ),
          createdAt: DateTime(2026, 1, 4),
        ),
        _trainer(
          id: 'trainer-vikram-malhotra',
          fullName: 'Vikram Malhotra',
          email: 'vikram.malhotra@demo.com',
          phone: '+91 98205 56789',
          expertise: const [
            'Cyber Security',
            'Network Defense',
            'Ethical Hacking',
            'Threat Intelligence',
          ],
          qualifications:
              'B.Tech IT, CISSP, CEH (Certified Ethical Hacker)',
          experienceYears: 9,
          availability: const TrainerAvailability(
            weekdays: [
              'Monday',
              'Tuesday',
              'Wednesday',
              'Thursday',
            ],
            preferredTimeRange: 'Late Evening (06:00 PM - 09:00 PM)',
            unavailableNotes: 'Unavailable weekends',
            generalNotes:
                'Available for cybersecurity bootcamps and defensive security labs.',
          ),
          createdAt: DateTime(2026, 1, 5),
        ),
      ];

  Trainer _trainer({
    required String id,
    required String fullName,
    required String email,
    required String phone,
    required List<String> expertise,
    required String qualifications,
    required int experienceYears,
    required TrainerAvailability availability,
    required DateTime createdAt,
    String status = 'active',
  }) =>
      Trainer(
        id: id,
        instituteId: 'demo-institute',
        fullName: fullName,
        email: email,
        emailNormalized: email.trim().toLowerCase(),
        phone: phone,
        expertise: expertise,
        qualifications: qualifications,
        experienceYears: experienceYears,
        availability: availability,
        status: status,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
}
