/// Shared user-facing terms, kept in one place for consistent wording.
/// Prescription text entered or read from a prescription is never translated.
class AppStrings {
  static const appName = 'IMedsU';
  static const tagline = 'Your Medication. Your Schedule. Your Health.';

  // Actions
  static const scanPrescription = 'Scan Prescription';
  static const takePhoto = 'Take a Photo';
  static const chooseFromGallery = 'Choose from Gallery';
  static const typePrescription = 'Type Prescription';
  static const markAsTaken = 'Mark as Taken';
  static const undo = 'Undo';
  static const save = 'Save';
  static const cancel = 'Cancel';
  static const delete = 'Delete';
  static const saveAndSetReminders = 'Save and Set Reminders';
  static const addMedication = 'Add Medication';
  static const sendTestReminder = 'Send Test Reminder (1 minute)';

  // Dose statuses (only statuses backed by saved data)
  static const taken = 'Taken';
  static const upcoming = 'Upcoming';
  static const notTaken = 'Not Taken';
  static const overdue = 'Overdue';
  static const missed = 'Missed';
  static const missedGuidance = "If you're unsure what to do after missing a "
      'dose, consult your pharmacist or prescriber.';

  // Review statuses
  static const verified = 'Verified';
  static const readyToVerify = 'Ready to verify';
  static const needsAttention = 'Needs attention';
  static const iveVerifiedThis = "I've Verified This";

  static const medication = 'Medication';
  static const scheduledTime = 'Scheduled Time';

  static const reviewWarning =
      'Some prescription details may be unclear. Please verify them against '
      'your prescription or confirm them with your pharmacist.';

  static const disclaimer =
      'IMedsU helps you follow the instructions from your doctor or '
      'pharmacist. It does not give medical advice, diagnose conditions, or '
      'change doses. If anything is unclear, ask your doctor or pharmacist.';
}
