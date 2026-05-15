# Project Mapper
Project Mapper is a plugin for Godot 4.6+ that create an Entity Relationship Diagram for an entire codebase, and shows data stored inside each class script.

<img width="842" height="566" alt="1" src="https://github.com/user-attachments/assets/73745c92-1ab1-4cf7-a087-fa9f0be46433" />

# Features
The Project Mapper plugin scans your entire project codebase, then visualises the inheritance between classes in a graph format. This graph format shows information on every class, including their signals, variables, static functions, instance functions, built-in functions, override functions and TODOs. Additionally, the graph view shows function calls between classes, and the scenes in the filesystem that use your project's classes.

# Installation
1. Copy `addons/project_mapper/` into your project's `addons/` folder.
2. In Godot, go to **Project settings → Plugins**, and enable the **Project Mapper** plugin. This will automatically open the `Project Mapper` dock to the bottom of the Editor.

# The Project Mapper window
The `Project Mapper` window will automatically open when the plugin is enabled. It will also automatically scan the project, and organise the graph view. The window reacts automatically when the editor is saved.

## Toolbar
The top of the window contains the following controls for the graph view:
* **Reorganise Button**: Arranges all of the graph nodes.
* **Expand/Collapse All Button**: Opens the dropdowns on every graph node and reorganises the graph view.
* **Search Bar**: Highlights graph where the search query is present in the class's name or script.
* **Straight Lines Toggle**: Toggles the grpah view between straight or curved lines.
* **Sync selection Toggle**: By enablign this, graph nodes will automatically be selected if the class' file is open in the Script Editor.

## Graph Nodes
Each graph node contains information on each class, and how they relate to other classes.

<img width="114" height="345" alt="Screenshot 2026-05-15 at 11 23 04 am" src="https://github.com/user-attachments/assets/0b2987e6-f5a9-465f-843b-d3ee6bce3b29" />

Graph nodes include information about a class':
* Autoload status (Graph node will be colored separately if the class is an autoload, yellow by default)
* Name (Clicking this will select the graph node, and show the path of inheritance with a separate color, pink by default)
* Following generation children count
* Uses in the filesystem by scenes.
* Signals (Signals will be coloured differently if the signal is not emitted within the class)
* Variables
* Static functions
* Instance functions
* Built-in functions
* Override Functions (Functions will be coloured differently depending on if the parent's `super()` function is called)
* TODOs

Clicking any item in a graph node dropdown with the Script window open will go to the specific line where the item is defined.

## Connections
Opening a function dropdown shows the selected class' outgoing function calls (green by default), and which other classes are calling the selected classes functions (blue by default). By viewing this, it is possible to better track how classes interact with each other.

<img width="1042" height="1019" alt="2" src="https://github.com/user-attachments/assets/142514a8-4744-40eb-adb3-8989acb79bad" />

NOTE: The Project Mapper does not track function calls within a class.

# View settings
Finally, the `project_mapper_settings.tres` file contains settings you can use to control how you want the project to look. This includes various color and style options.

<img width="403" height="775" alt="Screenshot 2026-05-15 at 11 22 17 am" src="https://github.com/user-attachments/assets/411b2494-995f-441f-8572-09adfeb78d99" />

# License
MIT License. See `LICENSE` for details.
