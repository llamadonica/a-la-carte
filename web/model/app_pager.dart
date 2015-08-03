part of a_la_carte_models;

abstract class AppPager {
  int get selected;
  void set selected(int value);

  Project get project;
  void setToNewProject();
  void openProject(String uuid);
}
