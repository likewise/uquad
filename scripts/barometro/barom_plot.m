function barom_plot(alt, avg_size, indexes)
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
%function barom_plot(alt, avg_size, indexes)
%
% Plot altitud, raw and averaged.
% Multiple segments can be marked by providing indexing in INDEXES.
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
if(nargin < 3)
  indexes = -1;
end

figure;
% plot data
plot(alt(avg_size:end));
hold on; 
alt_moving_avg = moving_avg(alt,avg_size);
% plot avg
plot(alt_moving_avg(avg_size:end),'g--');
legend('Raw data',sprintf('Avg. over %d samples',avg_size))
ylabel('Altura respecto al nivel del mar (m)')
xlabel('# de muestra')

if(indexes ~= -1)
  % plot segment borders
  max_val = max(alt);
  stem(indexes,ones(length(indexes),1)*max_val,'k.');
%stem(indexes)
end

axis([1 length(alt) min(alt) max(alt)])
grid on
hold off
