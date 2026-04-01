import re

with open('./Mistia/App/RootTabView.swift', 'r') as f:
    content = f.read()

search = """      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.98))
        .opacity(isExpanded ? 0 : 1)
        .scaleEffect(isExpanded ? 0.72 : 1)
        .frame(width: Self.collapsedSize, height: Self.collapsedSize)
        .background {
            Circle()
                .stroke(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.3), lineWidth: 1)
                .opacity(isExpanded ? 0 : 1)
                .scaleEffect(isExpanded ? 0.72 : 1)
                .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)"""

replace = """      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 1.0))
        .opacity(isExpanded ? 0 : 1)
        .scaleEffect(isExpanded ? 0.72 : 1)
        .frame(width: Self.collapsedSize, height: Self.collapsedSize)
        .background {
            Circle()
                .fill(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.25))
                .opacity(isExpanded ? 0 : 1)
                .scaleEffect(isExpanded ? 0.72 : 1)
                .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)"""

content = content.replace(search, replace)

with open('./Mistia/App/RootTabView.swift', 'w') as f:
    f.write(content)
