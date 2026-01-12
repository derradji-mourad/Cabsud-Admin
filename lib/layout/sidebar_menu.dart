import 'package:flutter/material.dart';

class SidebarMenu extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const SidebarMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  bool isExpanded = true;  // controls if sidebar is expanded or collapsed

  final List<String> titles = const [
    "Live Requests",
    "Request History",
    "Add Driver",
    "Fare Management",
    "All Drivers",
    "Map Request"
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isExpanded ? 200 : 60,  // retractable width
      color: Colors.deepPurple.shade50,
      child: Column(
        children: [
          const SizedBox(height: 40),
          // Add a button to toggle the sidebar
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(
                isExpanded ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                color: Colors.deepPurple,
              ),
              onPressed: () {
                setState(() {
                  isExpanded = !isExpanded;
                });
              },
            ),
          ),
          const SizedBox(height: 20),
          // Menu items
          Expanded(
            child: ListView.builder(
              itemCount: titles.length,
              itemBuilder: (context, i) {
                return ListTile(
                  selected: i == widget.selectedIndex,
                  selectedTileColor: Colors.deepPurple.shade100,
                  leading: Icon(
                    // Provide icons or use placeholders
                    Icons.circle,
                    size: 20,
                    color: i == widget.selectedIndex
                        ? Colors.deepPurple
                        : Colors.grey,
                  ),
                  title: isExpanded
                      ? Text(
                    titles[i],
                    style: TextStyle(
                      color: i == widget.selectedIndex
                          ? Colors.deepPurple
                          : Colors.black87,
                      fontWeight: i == widget.selectedIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  )
                      : null,
                  onTap: () => widget.onItemSelected(i),
                  horizontalTitleGap: 0,
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: isExpanded ? 16 : 8),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
