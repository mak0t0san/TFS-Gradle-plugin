using System;
using System.IO;
using System.Xml;
using System.Collections.Generic;
using System.Diagnostics;
using System.Activities;
using Microsoft.TeamFoundation.Build.Client;
using Microsoft.TeamFoundation.Build.Workflow.Activities;

namespace DeploymentToAzureVM
{
    
    public class DeploymentToAzureVM : CodeActivity
    {
        // VM Config File XML Elements
        private const string VM = "VM";
        private const string IMAGE_TYPE = "ImageType";
        private const string DNS = "DNS";
        private const string USER_NAME = "UserName";
        private const string DEPLOYMENT_PATH = "DeploymentPath";
        private const string SSH_PORT = "StandaloneSSHPublicPort";
        private const string PASSWORD = "Password";
        private const string SSH_KEY_PATH = "SSHPrivateKeyPath";
        private const string WINRM_PORT = "WinRMPort";

        // VM Config File XML Values
        private const string LINUX = "Linux";
        private const string WINDOWS = "Windows";
        
        // Holds all the XML Elements and Values within each <VM>...</VM> tags
        private Dictionary<string, string> vmConfig;
        
        // Holds the current XML Element being read. Used for logging in case of errors.
        private string vmConfigElementLog;

        // When PSCP command is run, it will be interactive and will ask for a confirmation
        // of the VM's RSA Key Fingerprint. Hence piping "echo y" will auto-answer it.
        string pscpCmd = "echo y | pscp";

        List<string> winRSCmds = new List<string>();
        string winRSCmd = "";

        // Hold the WinRS command after masking the password.
        // This will be used for logging.
        List<string> winRSCmdsMasked = new List<string>();
        string winRSCmdMasked = "winrs";

        int buildOutputDirParentPathLen = 0;

        string deploymentDir;

        private CodeActivityContext context;

        [RequiredArgument]
        public InArgument<string> BuildOutputPath { get; set; }

        [RequiredArgument]
        public InArgument<string> AzureVMsConfigFile { get; set; }

        protected override void Execute(CodeActivityContext context)
        {
            this.context = context;

            readVMConfigAndDeploy();
        }

        private void readVMConfigAndDeploy()
        {
            // Create XML reader settings
            XmlReaderSettings settings = new XmlReaderSettings();
            settings.IgnoreComments = true;
            settings.IgnoreWhitespace = true;

            XmlReader reader = XmlReader.Create(context.GetValue(this.AzureVMsConfigFile), settings);

            string key;
            string value;

            while (reader.Read())
            {
                this.vmConfig = new Dictionary<string, string>();
                this.vmConfigElementLog = "";

                this.pscpCmd = "/C echo y | pscp";
                
                this.winRSCmds = new List<string>();
                this.winRSCmd = "";
                this.winRSCmdsMasked = new List<string>();
                this.winRSCmdMasked = "winrs";
                this.buildOutputDirParentPathLen = 0;
                this.deploymentDir = "";

                if (reader.NodeType == XmlNodeType.Element && String.Compare(reader.Name, VM, true) == 0)
                {
                    // Read all the elements within <VM>...</VM>
                    while (reader.Read())
                    {
                        key = "";
                        value = "";

                        if (reader.NodeType == XmlNodeType.Element)
                        {
                            key = reader.Name;
                            reader.Read();
                            if (reader.NodeType == XmlNodeType.Text)
                            {
                                value = reader.Value;
                            }
                            this.vmConfig.Add(key, value);
                        }
                        else if (reader.NodeType == XmlNodeType.EndElement && String.Compare(reader.Name, VM, true) == 0)
                        {
                            // Finished reading all elements within <VM>...</VM>. Now process them.
                            try
                            {
                                this.vmConfigElementLog = IMAGE_TYPE;
                                if (String.Compare(this.vmConfig[IMAGE_TYPE], LINUX, true) == 0)
                                {
                                    constructPSCPCommand();
                                    executeCommand("cmd", pscpCmd);
                                }
                                else if (String.Compare(this.vmConfig[IMAGE_TYPE], WINDOWS, true) == 0)
                                {
                                    constructWinRSCommands();

                                    for (int i=0; i < this.winRSCmds.Count; i++)
                                    {
                                        context.TrackBuildMessage(this.winRSCmdsMasked[i], BuildMessageImportance.High);
                                        executeCommand("winrs", this.winRSCmds[i]);
                                    }
                                }
                                else
                                {
                                    throw new Exception("Supported Image types are Windows and Linux only!!");
                                }
                            }
                            catch (KeyNotFoundException knfe)
                            {
                                context.TrackBuildError("The element '" + this.vmConfigElementLog
                                    + "' is missing in the VM Config file!! \n" + knfe.StackTrace);
                                throw knfe;
                            }

                            // Break from the inner loop which is reading from <VM>...till </VM>, 
                            // so that you fetch the next set of <VM>...</VM> values
                            break;
                        }
                    }
                }
            }
        }

        private void constructPSCPCommand()
        {
            // Hold the PSCP commands after masking the password and SSH Key Path.
            // This will be used for logging.
            string pscpCmdMasked;

            this.vmConfigElementLog = "";

            try
            {
                this.vmConfigElementLog = USER_NAME;
                this.pscpCmd += " -l " + this.vmConfig[USER_NAME]; 					// Append user name
                pscpCmdMasked = this.pscpCmd;

                // Password or SSH Key path needs to be present
                if (this.vmConfig.ContainsKey(PASSWORD))
                {
                    this.pscpCmd += " -pw " + this.vmConfig[PASSWORD];				// Append password
                    pscpCmdMasked += " -pw ****";							    // To avoid logging the actual password
                }
                else if (this.vmConfig.ContainsKey(SSH_KEY_PATH))
                {
                    this.pscpCmd += " -i \"" + this.vmConfig[SSH_KEY_PATH] + "\""; 	// Append SSH Private Key Path
                    pscpCmdMasked += " -i ****";							    // To avoid logging the actual SSH Key Path
                }
                else
                {
                    // Neither password nor SSH Key are provided
                    throw new Exception("Neither Password nor SSH Key Path is provided. Check the VM Config again!!");
                }

                this.vmConfigElementLog = SSH_PORT;
                this.pscpCmd += " -P " + this.vmConfig[SSH_PORT];						                    // Append SSH Port
                pscpCmdMasked += " -P " + this.vmConfig[SSH_PORT];

                this.pscpCmd += " -r \"" + context.GetValue(this.BuildOutputPath) + "\" ";			// Append Build Output Folder
                pscpCmdMasked += " -r \"" + context.GetValue(this.BuildOutputPath) + "\" ";

                this.vmConfigElementLog = DNS + " OR " + DEPLOYMENT_PATH;
                this.pscpCmd += this.vmConfig[DNS] + ":" + this.vmConfig[DEPLOYMENT_PATH];	                    // Append DNS and Deployment path
                pscpCmdMasked += this.vmConfig[DNS] + ":" + this.vmConfig[DEPLOYMENT_PATH];

                context.TrackBuildMessage(pscpCmdMasked, BuildMessageImportance.High);
            }
            catch (KeyNotFoundException knfe)
            {
                context.TrackBuildError("The element '" + this.vmConfigElementLog
                    + "' is missing in the VM Config file!! \n" + knfe.StackTrace);
                throw knfe;
            }
        }

        private void constructWinRSCommands()
        {
            this.vmConfigElementLog = "";

            try
            {
                // Append DNS and WinRM port
                this.vmConfigElementLog = DNS + " OR " + WINRM_PORT;
                this.winRSCmd += " -r:http://" + this.vmConfig[DNS] + ":" + this.vmConfig[WINRM_PORT];

                // Append user name
                this.vmConfigElementLog = USER_NAME;
                this.winRSCmd += " -u:" + this.vmConfig[USER_NAME];
                this.winRSCmdMasked += this.winRSCmd;

                // Append password
                this.winRSCmd += " -p:" + this.vmConfig[PASSWORD];
                this.winRSCmdMasked += " -p:****";				// To avoid logging the actual password

                this.deploymentDir = this.vmConfig[DEPLOYMENT_PATH];
                string buildOutputDir = context.GetValue(this.BuildOutputPath);
                this.buildOutputDirParentPathLen = (buildOutputDir.Substring(0, buildOutputDir.LastIndexOf("\\"))).Length + 1;

                string buildOutputDirName = buildOutputDir.Substring(buildOutputDir.LastIndexOf("\\") + 1);
                
                // Remove the directory recursively, if it exists first
                winRSCmds.Add(this.winRSCmd + " \"if exist ^\"" + buildOutputDirName + "^\" rmdir /S /Q ^\"" + buildOutputDir + "^\"\"");
                winRSCmdsMasked.Add(this.winRSCmdMasked + " \"if exist ^\"" + buildOutputDirName + "^\" rmdir /S /Q ^\"" + buildOutputDir + "^\"\"");

                winRSCmds.Add(this.winRSCmd + " \"mkdir ^\"" + buildOutputDirName + "^\"\"");
                winRSCmdsMasked.Add(this.winRSCmdMasked + " \"mkdir ^\"" + buildOutputDirName + "^\"\"");

                browseDirCopyContents(buildOutputDir);
            }
            catch (KeyNotFoundException knfe)
            {
                context.TrackBuildError("The element '" + this.vmConfigElementLog
                    + "' is missing in the VM Config file!! \n" + knfe.StackTrace);
                throw knfe;
            }            
        }

        private void browseDirCopyContents(string directory)
        {
            string dirName;
            string fileName;

            try
            {
                foreach (string d in Directory.GetDirectories(directory))
                {
                    // We only need the directory name from the build output directory onwards.
                    // So trim the initial part of the full path.
                    // Then prefix the path with the deployment directory path.
                    dirName = this.deploymentDir + d.Remove(0, this.buildOutputDirParentPathLen);
                    winRSCmds.Add(this.winRSCmd + " \"mkdir ^\"" + dirName + "^\"\"");
                    winRSCmdsMasked.Add(this.winRSCmdMasked + " \"mkdir ^\"" + dirName + "^\"\"");

                    foreach (string f in Directory.GetFiles(d))
                    {
                        FileStream readStream = new FileStream(f, FileMode.Open);
                        BinaryReader readBinary = new BinaryReader(readStream);
                        int pos = 0;
                        int len = (int)readBinary.BaseStream.Length;
                        byte msg;

                        fileName = this.deploymentDir + f.Remove(0, this.buildOutputDirParentPathLen);

                        // Extract the contents of the local file and append to the remote file
                        while (pos < len)
                        {
                            msg = readBinary.ReadByte();
                            winRSCmds.Add(this.winRSCmd + " \"echo " + msg + " >> ^\"" + fileName + "^\"\"");
                            winRSCmdsMasked.Add(this.winRSCmdMasked + " \"echo " + msg + " >> ^\"" + fileName + "^\"\"");
                            pos += sizeof(byte);
                        }
                    }

                    browseDirCopyContents(d);
                }
            }
            catch (Exception e)
            {
                context.TrackBuildError("Error occurred while browsing directory: " + directory);
                throw e;
            }            
        }

        private void executeCommand(string cmd, string cmdArgs)
        {
            ProcessStartInfo procStartInfo;
            Process proc;

            procStartInfo = new ProcessStartInfo(cmd, cmdArgs);

            // Redirect the standard input, output and error to the Process.StandardInput, Process.StandardOutput and 
            // Process.StandardError StreamReader.
            procStartInfo.RedirectStandardInput = true;
            procStartInfo.RedirectStandardOutput = true;
            procStartInfo.RedirectStandardError = true;

            procStartInfo.UseShellExecute = false;

            // Do not create the black window.
            procStartInfo.CreateNoWindow = true;

            proc = new Process();
            proc.StartInfo = procStartInfo;
            proc.Start();

            // Get the output and error into a string
            string result = proc.StandardOutput.ReadToEnd();
            string error = proc.StandardError.ReadToEnd();

            // Display the command output / error
            if (String.IsNullOrEmpty(error))
            {
                context.TrackBuildMessage(result, BuildMessageImportance.High);
            }
            else
            {
                // This is done so that the interactive prompt is not considered as error.
                // The 'echo y' would supply the input.
                if (cmd.Contains("pscp") && error.StartsWith("The server's host key is not cached in the registry"))
                {
                    // Log the Standard Output and not the Error, because we have provided the interactive 
                    // input via 'echo y' for pscp command
                    context.TrackBuildMessage(result, BuildMessageImportance.High);
                }
                else
                {
                    context.TrackBuildError(error);
                }
            }
        }
    }
}
