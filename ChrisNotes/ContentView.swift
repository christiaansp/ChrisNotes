import SwiftUI

struct SummarizationResponse: Codable {
    let summary_text: String
}

class SummarizationService {
    static func summarizeText(_ text: String) async throws -> String {
        let url = URL(string: "https://api-inference.huggingface.co/models/facebook/bart-large-cnn")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer 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", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "inputs": text,
            "parameters": ["max_length": 130, "min_length": 30]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            print("Raw JSON Response: \(json)")
        }

        let summaries = try JSONDecoder().decode([SummarizationResponse].self, from: data)
        return summaries.first?.summary_text ?? "Could not generate summary."
    }
}

struct Tag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: String
    
    static let availableColors = [
        "red", "orange", "yellow", "green", "blue", "purple", "gray"
    ]
    
    func getColor() -> Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray": return .gray
        default: return .blue
        }
    }
}

struct Note: Identifiable, Codable {
    var id = UUID()
    var content: String
    var dateCreated: Date
    var summary: String?
    var tagIds: Set<UUID> = []
    
    var title: String {
        let firstLine = content.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }
}

class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    @Published var tags: [Tag] = []
    @Published var selectedNote: Note?
    @Published var isSummarizing = false
    @Published var selectedTags: Set<UUID> = []
    
    var isDirectorySelected: Bool {
        FileManager.default.fileExists(atPath: documentsDirectory.path)
    }
    
    private var documentsDirectory: URL {
        let localDocuments = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .deletingLastPathComponent()
            .appendingPathComponent("Movies")
        
        return localDocuments.appendingPathComponent("ChrisNotes", isDirectory: true)
    }
    
    private var notesFileURL: URL {
        documentsDirectory.appendingPathComponent("notes.json")
    }
    
    private var tagsFileURL: URL {
        documentsDirectory.appendingPathComponent("tags.json")
    }
    
    init() {
        try? FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
        loadTags()
        loadNotes()
    }
    
    private func loadTags() {
        do {
            let data = try Data(contentsOf: tagsFileURL)
            tags = try JSONDecoder().decode([Tag].self, from: data)
        } catch {
            print("Failed to load tags: \(error)")
            tags = []
        }
    }
    
    private func saveTags() {
        do {
            let encoded = try JSONEncoder().encode(tags)
            try encoded.write(to: tagsFileURL)
        } catch {
            print("Failed to save tags: \(error)")
        }
    }
    
    private func loadNotes() {
        print("Attempting to load notes from: \(notesFileURL.path)")
        do {
            let data = try Data(contentsOf: notesFileURL)
            let decoded = try JSONDecoder().decode([Note].self, from: data)
            notes = decoded
            print("Successfully loaded \(notes.count) notes")
            
            if let selectedNoteID = UserDefaults.standard.string(forKey: "selected_note_id"),
               let uuid = UUID(uuidString: selectedNoteID),
               let note = notes.first(where: { $0.id == uuid }) {
                selectedNote = note
            }
        } catch {
            print("Failed to load notes: \(error)")
            notes = []
        }
    }
    
    private func saveNotes() {
        do {
            print("Attempting to save notes to: \(notesFileURL.path)")
            let encoded = try JSONEncoder().encode(notes)
            try encoded.write(to: notesFileURL)
            UserDefaults.standard.set(selectedNote?.id.uuidString, forKey: "selected_note_id")
            print("Successfully saved notes")
        } catch {
            print("Failed to save notes: \(error)")
        }
    }
    
    func addTag(name: String, color: String) {
        let newTag = Tag(name: name, color: color)
        tags.append(newTag)
        saveTags()
    }
    
    func deleteTag(_ tag: Tag) {
        for noteIndex in notes.indices {
            notes[noteIndex].tagIds.remove(tag.id)
        }
        saveNotes()
        
        tags.removeAll { $0.id == tag.id }
        saveTags()
    }
    
    func toggleTagForNote(_ tag: Tag, note: Note) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == note.id }) else { return }
        
        if notes[noteIndex].tagIds.contains(tag.id) {
            notes[noteIndex].tagIds.remove(tag.id)
        } else {
            notes[noteIndex].tagIds.insert(tag.id)
        }
        
        if selectedNote?.id == note.id {
            selectedNote = notes[noteIndex]
        }
        
        saveNotes()
    }
    
    func addNote() {
        let newNote = Note(content: "", dateCreated: Date())
        notes.append(newNote)
        selectedNote = newNote
        saveNotes()
    }
    
    func updateNote(_ note: Note, content: String) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = notes[index]
            updatedNote.content = content
            notes[index] = updatedNote
            selectedNote = updatedNote
            objectWillChange.send()
            saveNotes()
        }
    }
    
    func deleteNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            if selectedNote?.id == note.id {
                selectedNote = notes.first
            }
            saveNotes()
        }
    }
    
    @MainActor
    func summarizeSelectedNote() async {
        guard let note = selectedNote, !note.content.isEmpty else { return }
        
        isSummarizing = true
        
        do {
            let summary = try await SummarizationService.summarizeText(note.content)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                var updatedNote = notes[index]
                updatedNote.summary = summary
                notes[index] = updatedNote
                selectedNote = updatedNote
                saveNotes()
            }
        } catch {
            print("Summarization error: \(error)")
        }
        
        isSummarizing = false
    }
}

struct TagView: View {
    let tag: Tag
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(tag.getColor())
                .frame(width: 8, height: 8)
            Text(tag.name)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.gray.opacity(0.2) : Color.clear)
        )
    }
}

struct SidebarView: View {
    @ObservedObject var notesManager: NotesManager
    @Binding var currentContent: String
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var selectedColor = "blue"
    
    var filteredNotes: [Note] {
        if notesManager.selectedTags.isEmpty {
            return notesManager.notes
        }
        return notesManager.notes.filter { note in
            !note.tagIds.isDisjoint(with: notesManager.selectedTags)
        }
    }
    
    var body: some View {
        VStack {
            Section(header:
                HStack {
                    Text("Tags")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingAddTag = true }) {
                        Image(systemName: "plus")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            ) {
                ForEach(notesManager.tags) { tag in
                    TagView(tag: tag, isSelected: notesManager.selectedTags.contains(tag.id))
                        .onTapGesture {
                            if notesManager.selectedTags.contains(tag.id) {
                                notesManager.selectedTags.remove(tag.id)
                            } else {
                                notesManager.selectedTags.insert(tag.id)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                notesManager.deleteTag(tag)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            List(filteredNotes) { note in
                VStack(alignment: .leading) {
                    Text(note.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !note.tagIds.isEmpty {
                        HStack {
                            ForEach(notesManager.tags.filter { note.tagIds.contains($0.id) }) { tag in
                                Circle()
                                    .fill(tag.getColor())
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(notesManager.selectedNote?.id == note.id ? Color.blue.opacity(0.2) : Color.clear)
                )
                .onTapGesture {
                    notesManager.selectedNote = note
                    currentContent = note.content
                }
                .contextMenu {
                    Menu("Tags") {
                        ForEach(notesManager.tags) { tag in
                            Button {
                                notesManager.toggleTagForNote(tag, note: note)
                            } label: {
                                Label(tag.name, systemImage: note.tagIds.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                    
                    Button(role: .destructive) {
                        notesManager.deleteNote(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .listStyle(SidebarListStyle())
            
            Button(action: {
                notesManager.addNote()
                if let newNote = notesManager.selectedNote {
                    currentContent = newNote.content
                }
            }) {
                Label("New Note", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
            .padding(.bottom)
        }
        .frame(minWidth: 200, maxWidth: 250)
        .sheet(isPresented: $showingAddTag) {
            VStack(spacing: 16) {
                Text("New Tag")
                    .font(.headline)
                
                TextField("Tag Name", text: $newTagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Picker("Color", selection: $selectedColor) {
                    ForEach(Tag.availableColors, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(Tag(name: "", color: color).getColor())
                                .frame(width: 16, height: 16)
                            Text(color.capitalized)
                        }
                        .tag(color)
                    }
                }
                
                HStack {
                    Button("Cancel") {
                        showingAddTag = false
                    }
                    
                    Button("Add") {
                        if !newTagName.isEmpty {
                            notesManager.addTag(name: newTagName, color: selectedColor)
                            newTagName = ""
                            showingAddTag = false
                        }
                    }
                    .disabled(newTagName.isEmpty)
                }
                .padding(.top)
            }
            .padding()
            .frame(width: 300)
        }
    }
}

struct ContentView: View {
    @StateObject var notesManager = NotesManager()
    @State private var currentContent: String = ""
    
    var body: some View {
        NavigationView {
            SidebarView(notesManager: notesManager, currentContent: $currentContent)
            
            if let selectedNote = notesManager.selectedNote {
                VStack(spacing: 0) {
                    HStack {
                        Text(selectedNote.dateCreated.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            ForEach(notesManager.tags.filter { selectedNote.tagIds.contains($0.id) }) { tag in
                                TagView(tag: tag, isSelected: false)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await notesManager.summarizeSelectedNote()
                            }
                        }) {
                            Label("Summarize", systemImage: "text.quote")
                        }
                        .disabled(notesManager.isSummarizing || selectedNote.content.isEmpty)
                                                .opacity(notesManager.isSummarizing ? 0.5 : 1)
                                            }
                                            .padding([.top, .horizontal], 8)
                                            
                                            if let summary = selectedNote.summary {
                                                VStack(alignment: .leading) {
                                                    Text("Summary")
                                                        .font(.headline)
                                                    Text(summary)
                                                        .font(.system(size: 14))
                                                        .padding(8)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .background(Color.secondary.opacity(0.1))
                                                        .cornerRadius(8)
                                                }
                                                .padding()
                                            }
                                            
                                            ScrollView {
                                                ZStack(alignment: .topLeading) {
                                                    VStack(spacing: 0) {
                                                        ForEach(0..<1000) { _ in
                                                            Divider()
                                                                .padding(.top, 24)
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity)
                                                    
                                                    TextEditor(text: Binding(
                                                        get: { currentContent },
                                                        set: { newValue in
                                                            currentContent = newValue
                                                            notesManager.updateNote(selectedNote, content: newValue)
                                                        }
                                                    ))
                                                    .font(.system(size: 16, weight: .regular, design: .default))
                                                    .lineSpacing(7)
                                                    .scrollContentBackground(.hidden)
                                                    .background(Color.clear)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.horizontal)
                                                    .disableAutocorrection(false)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    } else {
                                        Text("Select or create a note")
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                                .frame(minWidth: 600, minHeight: 400)
                                .navigationTitle("Notes")
                            }
                        }

                        #Preview {
                            ContentView()
                        }
