using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace BuildProcess.CustomEditors
{
    public partial class PasswordDialog : Form
    {
        public PasswordDialog()
        {
            InitializeComponent();
        }
        
        public string Password
        {
            get
            {
                return PasswordTextbox.Text;
            }
            set
            {
                PasswordTextbox.Text = value;
            }
        }

        private void buttonClear_Click(object sender, EventArgs e)
        {
            PasswordTextbox.Clear();
        }
    }
}
