//
//  SecondViewController.swift
//  cert-wallet
//
//  Created by Chris Downie on 8/8/16.
//  Copyright © 2016 Digital Certificates Project.
//

import UIKit

class CertificatesViewController: UITableViewController {
    var certificates = [Certificate]()
    let cellReuseIdentifier = "CertificateTableViewCell"
    let detailSegueIdentifier = "CertificateDetail"

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        loadCertificates()
        
        NotificationCenter.default.addObserver(self, selector: #selector(loadCertificates), name: NotificationNames.allDataReset, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleImportNotification(_:)), name: NotificationNames.importCertificate, object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == detailSegueIdentifier {
            let destination = segue.destination as? CertificateDetailViewController
            if let selectedIndex = tableView.indexPathForSelectedRow?.row {
                destination?.certificate = certificates[selectedIndex]
            } else {
                destination?.certificate = nil
            }
        }
    }


    @IBAction func importTapped(_ sender: UIBarButtonItem) {
        let whichImport = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        whichImport.addAction(UIAlertAction(title: "Import File", style: .default, handler: { (action) in
            let controller = UIDocumentPickerViewController(documentTypes: ["public.json"], in: .import)
            controller.delegate = self
            controller.modalPresentationStyle = .formSheet
            
            self.present(controller, animated: true, completion: nil)
        }))
        
        whichImport.addAction(UIAlertAction(title: "Import from URL", style: .default, handler: { (action) in
            let urlPrompt = UIAlertController(title: nil, message: "Enter the URL to import from below", preferredStyle: .alert)
            urlPrompt.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "URL"
            })
            
            urlPrompt.addAction(UIAlertAction(title: "Import", style: .default, handler: { (_) in
                guard let urlField = urlPrompt.textFields?.first,
                    let trimmedText = urlField.text?.trimmingCharacters(in: CharacterSet.whitespaces),
                    let url = URL(string: trimmedText) else {
                    return
                }

                self.importCertificate(at: url)
            }))

            self.present(urlPrompt, animated: true, completion: nil)
        }))
        
        whichImport.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(whichImport, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return certificates.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier)!
        let certificate = certificates[indexPath.row]
        
        cell.textLabel?.text = certificate.title
        cell.detailTextLabel?.text = certificate.subtitle
        cell.imageView?.image = UIImage(data: certificate.image)

        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let deleteAction = UITableViewRowAction(style: .destructive, title: "Delete") { [weak self] (action, indexPath) in
            let deletedCertificate : Certificate! = self?.certificates.remove(at: indexPath.row)
            
            let documentsDirectory = URL(fileURLWithPath: Paths.certificateDirectory)
            let certificateFilename = self?.filenameFor(certificate: deletedCertificate) ?? ""
            let filePath = URL(fileURLWithPath: certificateFilename, relativeTo: documentsDirectory)
            do {
                try FileManager.default.removeItem(at: filePath)
                tableView.reloadData()
            } catch {
                self?.certificates.insert(deletedCertificate, at: indexPath.row)
                
                let alertController = UIAlertController(title: "Couldn't delete file", message: "Something went wrong deleting that certificate.", preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self?.present(alertController, animated: true, completion: nil)
            }
            
        }
        return [ deleteAction ]
    }
    
    func handleImportNotification(_ note: Notification) {
        guard let fileURL = note.object as? URL else {
            // This is a developer failure. It means we sent the notification without a URL paylaod. No need to inform the user. 
            return
        }
        let existingCertificateCount = certificates.count
        importCertificate(at: fileURL)
        
        if certificates.count > existingCertificateCount {
            let lastRow = IndexPath(row: certificates.count - 1, section: 0)
            tableView.selectRow(at: lastRow, animated: true, scrollPosition: .none)
            performSegue(withIdentifier: detailSegueIdentifier, sender: nil)
        } else {
            let alertController = UIAlertController(title: "Import failed", message: "It doesn't look like that's a valid certificate", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alertController, animated: true, completion: nil)
        }
    }
    
    func importCertificate(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            let alertController = UIAlertController(title: "Couldn't read file", message: "Something went wrong trying to open the file.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alertController] action in
                alertController?.dismiss(animated: true, completion: nil)
                }))
            present(alertController, animated: true, completion: nil)
            return
        }
        
        guard let certificate = CertificateParser.parse(data: data) else {
            let alertController = UIAlertController(title: "Invalid Certificate", message: "That doesn't appear to be a valid Certificate file.", preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alertController] action in
                alertController?.dismiss(animated: true, completion: nil)
                }))
            present(alertController, animated: true, completion: nil)
            return
        }
        
        // At this point, data is totally a valid certificate. Let's save that to the documents directory.
        let filename = filenameFor(certificate: certificate)
        save(certificateData: data, withFilename: filename)
        
        // TODO: We should check and see if that cert is already in the array.
        
        certificates.append(certificate)
        
        // TODO: We should do an insert animation rather than a full table reload.
        tableView.reloadData()
    }

    func loadCertificates() {
        let documentsDirectory = Paths.certificateDirectory
        let directoryUrl = URL(fileURLWithPath: documentsDirectory)
        let filenames = (try? FileManager.default.contentsOfDirectory(atPath: documentsDirectory)) ?? []
        
        certificates = filenames.flatMap { (filename) in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filename, relativeTo: directoryUrl)),
                let certificate = CertificateParser.parse(data: data) else {
                    // Certificate is invalid. Don't load it.
                    return nil
            }
            return certificate
        }
        
        tableView.reloadData()
    }
    
    func filenameFor(certificate : Certificate) -> String {
        return "\(certificate.id)".replacingOccurrences(of: "/", with: "_")
    }
}

extension CertificatesViewController : UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        importCertificate(at: url)
    }
    
    @discardableResult func save(certificateData data: Data, withFilename filename: String) -> Bool {
        let documentsDirectory = Paths.certificateDirectory
        let filePath = "\(documentsDirectory)/\(filename)"
        if FileManager.default.fileExists(atPath: filePath) {
            print("File \(filename) already exists")
            // TODO: Should we make a copy? Check if it's equal?
            return false
        } else {
            // TODO: What file attributes would be useful here?
            return FileManager.default.createFile(atPath: filePath, contents: data, attributes: nil)
        }
    }
}
