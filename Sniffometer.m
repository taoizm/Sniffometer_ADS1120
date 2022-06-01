classdef Sniffometer < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        SniffometerUIFigure      matlab.ui.Figure
        GridLayout               matlab.ui.container.GridLayout
        SerialPortDropDownLabel  matlab.ui.control.Label
        SerialPortDropDown       matlab.ui.control.DropDown
        ConnectButton            matlab.ui.control.Button
        DirectoryEditFieldLabel  matlab.ui.control.Label
        DirectoryEditField       matlab.ui.control.EditField
        UIGetDirButton           matlab.ui.control.Button
        DataStreamSwitchLabel    matlab.ui.control.Label
        RecordButton             matlab.ui.control.StateButton
        DataStreamSwitch         matlab.ui.control.Switch
        AcceptTriggerCheckBox    matlab.ui.control.CheckBox
        REditFieldLabel          matlab.ui.control.Label
        REditField               matlab.ui.control.NumericEditField
        BEditFieldLabel          matlab.ui.control.Label
        BEditField               matlab.ui.control.NumericEditField
        NotificationLabel        matlab.ui.control.Label
        UIAxes                   matlab.ui.control.UIAxes
    end

    properties (Constant)
        BaudRate = 115200;   % Baud rate for serial communication
        SamplingRate = 1000; % Hz
        BufferLength = 1000; % Number of samples in the buffer
        Gain = 4;    % ADC gain 
        Rref = 6800; % Ohm
    end
    
    properties (Access = private)
        serialObj; % Serial object
        t = (1:Sniffometer.BufferLength)/Sniffometer.SamplingRate;
        buffer = zeros(1,Sniffometer.BufferLength);
        bufPos = 0;
        filename;
        fileID;
    end
    
    methods (Access = private)
        
        function serialHandler(app,~,~)
            if app.serialObj.NumBytesAvailable==0
                return % Avoid multiple callback to @app.serialHandler
            end
            opcode = app.serialObj.read(1,'char');
            switch opcode
                case 'D' % Data stream opcode
                    nSamples = app.serialObj.read(1,'uint8');
                    code = app.serialObj.read(nSamples,'int16');
                    idx = getRingBufferIndex(app,app.bufPos+1:app.bufPos+nSamples);
                    app.buffer(idx) = codeToTemp(app,double(code));
                    app.bufPos = idx(end);
                    app.updatePlot();
                    % Write raw data to DAT file
                    if app.RecordButton.Value
                        fwrite(app.fileID,code,'int16');
                    end
                case 'T' % Trigger opcode
                    if app.AcceptTriggerCheckBox.Value
                        % Start/Stop recording
                        app.RecordButton.Value = ~app.RecordButton.Value;
                        app.RecordButtonValueChanged();
                    end
            end
        end
        
        function updatePlot(app)
            plot(app.UIAxes,app.t,app.buffer);
        end
        
        function updateNotification(app,message)
            app.NotificationLabel.Text = sprintf('[%s] %s',datetime,message);
        end
        
        function idx = getRingBufferIndex(app,idx)
            idx = mod(idx-1,app.BufferLength)+1;
        end
        
        function temp = codeToTemp(app,code)
            % Convert 16-bit code to thermistor resistance
            % Assume AIN0=Rt/(Rref+Rt)*3.3V and AIN1=1.65V
            Rt = app.Rref * (2^14*app.Gain+code) ./ (2^14*app.Gain-code);
            % Convert thermistor resitatnce to temperature
            temp = 1 ./ (log(Rt/app.REditField.Value)/app.BEditField.Value + 1/(273.15+25)) - 273.15;
        end
    end   

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            app.SerialPortDropDown.Items = serialportlist;
            app.DirectoryEditField.Value = pwd;
            % Label formatting
            app.UIGetDirButton.Text = '...';
            app.AcceptTriggerCheckBox.Text = 'Accept trigger to start/stop recording';
            app.REditFieldLabel.Text = 'R0 (Ohm)';
            app.BEditFieldLabel.Text = 'B (K)';
            % Create plot
            app.updatePlot();
            app.updateNotification("Sniffometer initialized.");
        end

        % Value changed function: SerialPortDropDown
        function SerialPortDropDownValueChanged(app, event)
            app.SerialPortDropDown.Items = serialportlist;
        end

        % Button pushed function: ConnectButton
        function ConnectButtonPushed(app, event)
            app.serialObj = serialport(app.SerialPortDropDown.Value,app.BaudRate);
            app.serialObj.configureCallback('byte',1,@app.serialHandler);
            app.updateNotification(sprintf("Begin serial communication on %s.",app.SerialPortDropDown.Value));
        end

        % Button pushed function: UIGetDirButton
        function UIGetDirButtonPushed(app, event)
            mydir = uigetdir();
            if mydir~=0
               app.DirectoryEditField.Value = mydir; 
            end
        end

        % Value changed function: DataStreamSwitch
        function DataStreamSwitchValueChanged(app, event)
            if ~isa(app.serialObj,'internal.Serialport')
                uialert(app.SniffometerUIFigure, ...
                    'Connect to Sniffometer acquisition board.', ...
                    'No serial connection');
                app.DataStreamSwitch.Value = 1-app.DataStreamSwitch.Value;
            else
                app.serialObj.write('S','char'); % Send start/stop data stream opcode
                if app.DataStreamSwitch.Value
                    app.updateNotification("Start data streaming.");
                else
                    app.updateNotification("Stop data streaming.");
                end                
            end
        end

        % Value changed function: RecordButton
        function RecordButtonValueChanged(app, event)
            if app.RecordButton.Value
                % Create a new file to log the raw data
                app.filename = fullfile( ...
                    app.DirectoryEditField.Value, ...
                    [datestr(datetime,'yyyy-mm-dd_HH-MM-SS') '.dat']);
                app.fileID = fopen(app.filename,'w');
                app.updateNotification("Start recording.");
            else
                fclose(app.fileID);
                % Delete unwritten DAT file
                if dir(app.filename).bytes==0
                    delete(app.filename);
                end
                app.updateNotification("Stop recording.");
            end
        end

        % Close request function: SniffometerUIFigure
        function SniffometerUIFigureCloseRequest(app, event)
            % Stop data stream if running
            if app.DataStreamSwitch.Value
                app.DataStreamSwitch.Value = 1-app.DataStreamSwitch.Value;
                app.DataStreamSwitchValueChanged();
            end
            % Closes the file if opened
            try
                fclose(app.fileID);
            catch

            end
            % Delete app object
            delete(app)            
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create SniffometerUIFigure and hide until all components are created
            app.SniffometerUIFigure = uifigure('Visible', 'off');
            app.SniffometerUIFigure.Position = [100 100 640 480];
            app.SniffometerUIFigure.Name = 'Sniffometer';
            app.SniffometerUIFigure.Icon = 'icon.png';
            app.SniffometerUIFigure.CloseRequestFcn = createCallbackFcn(app, @SniffometerUIFigureCloseRequest, true);

            % Create GridLayout
            app.GridLayout = uigridlayout(app.SniffometerUIFigure);
            app.GridLayout.ColumnWidth = {80, 60, 40, 60, '1x', 22, 80, 80};
            app.GridLayout.RowHeight = {22, 22, 22, 22, '1x', 22};

            % Create SerialPortDropDownLabel
            app.SerialPortDropDownLabel = uilabel(app.GridLayout);
            app.SerialPortDropDownLabel.HorizontalAlignment = 'right';
            app.SerialPortDropDownLabel.Layout.Row = 1;
            app.SerialPortDropDownLabel.Layout.Column = 1;
            app.SerialPortDropDownLabel.Text = 'Serial Port';

            % Create SerialPortDropDown
            app.SerialPortDropDown = uidropdown(app.GridLayout);
            app.SerialPortDropDown.Items = {};
            app.SerialPortDropDown.ValueChangedFcn = createCallbackFcn(app, @SerialPortDropDownValueChanged, true);
            app.SerialPortDropDown.Layout.Row = 1;
            app.SerialPortDropDown.Layout.Column = [2 3];
            app.SerialPortDropDown.Value = {};

            % Create ConnectButton
            app.ConnectButton = uibutton(app.GridLayout, 'push');
            app.ConnectButton.ButtonPushedFcn = createCallbackFcn(app, @ConnectButtonPushed, true);
            app.ConnectButton.Layout.Row = 1;
            app.ConnectButton.Layout.Column = 4;
            app.ConnectButton.Text = 'Connect';

            % Create DirectoryEditFieldLabel
            app.DirectoryEditFieldLabel = uilabel(app.GridLayout);
            app.DirectoryEditFieldLabel.HorizontalAlignment = 'right';
            app.DirectoryEditFieldLabel.Layout.Row = 2;
            app.DirectoryEditFieldLabel.Layout.Column = 1;
            app.DirectoryEditFieldLabel.Text = 'Directory';

            % Create DirectoryEditField
            app.DirectoryEditField = uieditfield(app.GridLayout, 'text');
            app.DirectoryEditField.Tooltip = {'Directory for saving raw data as a DAT file'};
            app.DirectoryEditField.Layout.Row = 2;
            app.DirectoryEditField.Layout.Column = [2 5];

            % Create UIGetDirButton
            app.UIGetDirButton = uibutton(app.GridLayout, 'push');
            app.UIGetDirButton.ButtonPushedFcn = createCallbackFcn(app, @UIGetDirButtonPushed, true);
            app.UIGetDirButton.Layout.Row = 2;
            app.UIGetDirButton.Layout.Column = 6;
            app.UIGetDirButton.Text = 'UIGetDir';

            % Create DataStreamSwitchLabel
            app.DataStreamSwitchLabel = uilabel(app.GridLayout);
            app.DataStreamSwitchLabel.HorizontalAlignment = 'center';
            app.DataStreamSwitchLabel.Layout.Row = 2;
            app.DataStreamSwitchLabel.Layout.Column = 8;
            app.DataStreamSwitchLabel.Text = 'Data Stream';

            % Create RecordButton
            app.RecordButton = uibutton(app.GridLayout, 'state');
            app.RecordButton.ValueChangedFcn = createCallbackFcn(app, @RecordButtonValueChanged, true);
            app.RecordButton.Text = 'Record';
            app.RecordButton.Layout.Row = 2;
            app.RecordButton.Layout.Column = 7;

            % Create DataStreamSwitch
            app.DataStreamSwitch = uiswitch(app.GridLayout, 'slider');
            app.DataStreamSwitch.ItemsData = [0 1];
            app.DataStreamSwitch.ValueChangedFcn = createCallbackFcn(app, @DataStreamSwitchValueChanged, true);
            app.DataStreamSwitch.Layout.Row = 1;
            app.DataStreamSwitch.Layout.Column = 8;
            app.DataStreamSwitch.Value = 0;

            % Create AcceptTriggerCheckBox
            app.AcceptTriggerCheckBox = uicheckbox(app.GridLayout);
            app.AcceptTriggerCheckBox.Tooltip = {'Automatically start redording by the trigger input if checked'};
            app.AcceptTriggerCheckBox.Text = 'Accept Trigger';
            app.AcceptTriggerCheckBox.Layout.Row = 3;
            app.AcceptTriggerCheckBox.Layout.Column = [2 5];

            % Create REditFieldLabel
            app.REditFieldLabel = uilabel(app.GridLayout);
            app.REditFieldLabel.HorizontalAlignment = 'right';
            app.REditFieldLabel.Layout.Row = 4;
            app.REditFieldLabel.Layout.Column = 1;
            app.REditFieldLabel.Text = 'R';

            % Create REditField
            app.REditField = uieditfield(app.GridLayout, 'numeric');
            app.REditField.ValueDisplayFormat = '%11.5g';
            app.REditField.Tooltip = {'Thermistor resistance at 298.15K (only for plotting)'};
            app.REditField.Layout.Row = 4;
            app.REditField.Layout.Column = 2;
            app.REditField.Value = 10740;

            % Create BEditFieldLabel
            app.BEditFieldLabel = uilabel(app.GridLayout);
            app.BEditFieldLabel.HorizontalAlignment = 'right';
            app.BEditFieldLabel.Layout.Row = 4;
            app.BEditFieldLabel.Layout.Column = 3;
            app.BEditFieldLabel.Text = 'B';

            % Create BEditField
            app.BEditField = uieditfield(app.GridLayout, 'numeric');
            app.BEditField.ValueDisplayFormat = '%11.5g';
            app.BEditField.Tooltip = {'B constant of the thermistor (only for plotting)'};
            app.BEditField.Layout.Row = 4;
            app.BEditField.Layout.Column = 4;
            app.BEditField.Value = 3450;

            % Create NotificationLabel
            app.NotificationLabel = uilabel(app.GridLayout);
            app.NotificationLabel.Layout.Row = 6;
            app.NotificationLabel.Layout.Column = [1 8];
            app.NotificationLabel.Text = 'Notification';

            % Create UIAxes
            app.UIAxes = uiaxes(app.GridLayout);
            xlabel(app.UIAxes, 'Time (sec)', 'Interpreter', 'none')
            ylabel(app.UIAxes, 'Temperature (\circC)', 'Interpreter', 'none')
            zlabel(app.UIAxes, 'Z', 'Interpreter', 'none')
            app.UIAxes.XLim = [0 1];
            app.UIAxes.YLim = [30 35];
            app.UIAxes.TickDir = 'out';
            app.UIAxes.Layout.Row = 5;
            app.UIAxes.Layout.Column = [1 8];

            % Show the figure after all components are created
            app.SniffometerUIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = Sniffometer

            runningApp = getRunningApp(app);

            % Check for running singleton app
            if isempty(runningApp)

                % Create UIFigure and components
                createComponents(app)

                % Register the app with App Designer
                registerApp(app, app.SniffometerUIFigure)

                % Execute the startup function
                runStartupFcn(app, @startupFcn)
            else

                % Focus the running singleton app
                figure(runningApp.SniffometerUIFigure)

                app = runningApp;
            end

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.SniffometerUIFigure)
        end
    end
end