part of dgs.models;

class Questionnaire {
  static Map<String,Questionnaire> _loadedQuestionnaires;
  static Map<String,Questionnaire> get loadedQuestionnaires {
    if (_loadedQuestionnaires == null)
      _loadedQuestionnaires = new Map<String,Questionnaire>();
    return _loadedQuestionnaires;
  }
  
  final String id;
  Questionnaire (String this.id) {
    loadedQuestionnaires[id] = this;
  }
  List<QuestionnaireQuestion> questions;
}

class QuestionnaireQuestion {
  final String id;
  QuestionnaireQuestion (String this.id);
  
  int weight;
  String text;
  
}


